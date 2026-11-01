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

    let settings: AppSettings
    let history: HistoryStore
    private let runner = SmartctlRunner.bundled()
    private let alertStateURL: URL
    private var alertState: AlertState
    private var timer: Timer?
    private var watcher: DiskWatcher?
    private var cancellables: Set<AnyCancellable> = []

    var overall: HealthLevel { HealthLevel.overall(disks.map { reports[$0.id]?.level ?? .unknown }) }

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
        // Перезапускаємо таймер і перераховуємо стан, коли змінюються налаштування.
        settings.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTimer()
                self?.reevaluate()
            }
            .store(in: &cancellables)
        watcher = DiskWatcher { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await runner.readAll()
        disks = result.disks.sorted { $0.deviceName.localizedStandardCompare($1.deviceName) == .orderedAscending }
        errors = result.errors
        lastUpdate = Date()
        reevaluate()

        history.append(disks, at: Date())
        try? history.save()

        let alerts = AlertEngine.diff(disks: disks, thresholds: settings.thresholds, state: &alertState)
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
            NSLog("DiskHealth: cannot save alert state: \(error)")
        }
    }
}
