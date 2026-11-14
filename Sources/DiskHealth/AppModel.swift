import Combine
import DiskHealthCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var disks: [DiskInfo] = []
    @Published private(set) var reports: [String: HealthReport] = [:]
    @Published private(set) var errors: [String] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var externalDisks: [ExternalDisk] = []
    /// Диски, для яких зараз виконується монтування чи розмонтування.
    @Published private(set) var busyDisks: Set<String> = []
    /// Остання помилка монтування за диском.
    @Published private(set) var mountErrors: [String: String] = [:]
    /// Заповненість за BSD-ім'ям цілого диска (`disk0`).
    @Published private(set) var spaces: [String: DiskSpace] = [:]

    let settings: AppSettings
    let history: HistoryStore
    private let runner = SmartctlRunner.bundled()
    private let diskutil = DiskutilRunner()
    private let alertStateURL: URL
    private var alertState: AlertState
    private var timer: Timer?
    private var watcher: DiskWatcher?
    private var cancellables: Set<AnyCancellable> = []

    var overall: HealthLevel { HealthLevel.overall(disks.map { reports[$0.id]?.level ?? .unknown }) }

    func external(for disk: DiskInfo) -> ExternalDisk? {
        externalDisks.first { "/dev/\($0.id)" == disk.deviceName }
    }

    func space(for disk: DiskInfo) -> DiskSpace? {
        spaces[disk.deviceName.replacingOccurrences(of: "/dev/", with: "")]
    }

    /// Зовнішні диски, яких не бачить `smartctl` (наприклад, флешки): їх теж має бути чим розмонтувати.
    var externalWithoutSmart: [ExternalDisk] {
        externalDisks.filter { ext in !disks.contains { $0.deviceName == "/dev/\(ext.id)" } }
    }

    init(settings: AppSettings) {
        self.settings = settings
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskHealth", isDirectory: true)
        history = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
        history.load()
        alertStateURL = dir.appendingPathComponent("alert-state.json")
        alertState = (try? Data(contentsOf: alertStateURL))
            .flatMap { try? JSONDecoder().decode(AlertState.self, from: $0) } ?? AlertState()
    }

    func start() {
        Notifier.requestAuthorization()
        scheduleTimer()
        // Перезапускаємо таймер, перераховуємо стан і перевіряємо пороги на вже зчитаних даних,
        // щоб нове попередження прийшло одразу, а не з наступним опитуванням.
        settings.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTimer()
                self?.reevaluate()
                self?.checkAlerts()
            }
            .store(in: &cancellables)
        watcher = DiskWatcher(onChange: { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }, onVolumesChange: { [weak self] in
            Task { @MainActor in await self?.refreshExternal() }
        })
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Спершу швидкий список томів: SMART сплячого USB-диска може читатися довго, а кнопка потрібна одразу.
        await refreshExternal()
        let result = await runner.readAll()
        disks = result.disks.sorted { $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending }
        errors = result.errors
        lastUpdate = Date()
        reevaluate()

        history.append(disks, at: Date())
        try? history.save()

        await refreshSpace()
    }

    func refreshExternal() async {
        do {
            externalDisks = try await diskutil.list()
        } catch {
            NSLog("DiskHealth: cannot list external disks: %@", String(describing: error))
        }
        await refreshSpace()
    }

    /// Перераховує заповненість усіх відомих дисків і перевіряє поріг.
    func refreshSpace() async {
        let ids = Set(disks.map { $0.deviceName.replacingOccurrences(of: "/dev/", with: "") } + externalDisks.map(\.id))
        guard let list = try? await diskutil.listAll() else { return }
        var result: [String: DiskSpace] = [:]
        for id in ids where id.hasPrefix("disk") {
            guard let groups = try? DiskSpaceCalculator.mountGroups(diskutilList: list, wholeDisk: id) else { continue }
            result[id] = DiskSpaceCalculator.combine(groups.map { $0.compactMap(Self.capacity) })
        }
        spaces = result
        checkAlerts()
    }

    /// Як у Finder: доступним вважається й місце, яке macOS звільнить сама (кеші, локальні знімки).
    nonisolated private static func capacity(at mountPoint: String) -> VolumeCapacity? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let v = try? URL(fileURLWithPath: mountPoint).resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity
        else { return nil }
        let available = v.volumeAvailableCapacityForImportantUsage ?? v.volumeAvailableCapacity.map(Int64.init) ?? 0
        return VolumeCapacity(totalBytes: Int64(total), availableBytes: available)
    }

    /// Розмонтовує змонтований диск або монтує розмонтований.
    func toggleMount(_ disk: ExternalDisk) async {
        guard busyDisks.insert(disk.id).inserted else { return }
        defer { busyDisks.remove(disk.id) }
        mountErrors[disk.id] = nil
        do {
            if disk.isMounted {
                try await diskutil.unmount(disk)
            } else {
                try await diskutil.mount(disk)
            }
        } catch {
            let reason = error.localizedDescription
            mountErrors[disk.id] = disk.isMounted
                ? String(localized: "Could not unmount. Close the apps using this disk. \(reason)")
                : String(localized: "Could not mount. \(reason)")
        }
        await refreshExternal()
    }

    private func checkAlerts() {
        guard lastUpdate != nil else { return }
        let t = settings.thresholds
        var alerts = AlertEngine.diff(disks: disks, thresholds: t, state: &alertState)
        // Ключ за серійним номером, а не за BSD-ім'ям: те змінюється після перепідключення.
        let spaceItems = disks.compactMap { d in space(for: d).map { SpaceAlertItem(id: d.id, name: d.model, space: $0) } }
            + externalWithoutSmart.compactMap { e in
                let name = e.volumes.first?.name ?? e.id
                return spaces[e.id].map { SpaceAlertItem(id: "volume:\(name)", name: name, space: $0) }
            }
        alerts += AlertEngine.diffSpace(spaceItems, thresholds: t, state: &alertState)
        if settings.notificationsEnabled { Notifier.post(alerts) }
        saveAlertState()
    }

    private func reevaluate() {
        let t = settings.thresholds
        reports = Dictionary(uniqueKeysWithValues: disks.map { ($0.id, HealthEvaluator.evaluate($0, t)) })
    }

    private func scheduleTimer() {
        let interval = TimeInterval(max(1, settings.pollMinutes) * 60)
        if let timer, timer.timeInterval == interval { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func saveAlertState() {
        do {
            try FileManager.default.createDirectory(at: alertStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(alertState).write(to: alertStateURL, options: .atomic)
        } catch {
            NSLog("DiskHealth: cannot save alert state: %@", String(describing: error))
        }
    }
}
