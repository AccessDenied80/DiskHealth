# DiskHealth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu-bar macOS app that reads SMART data of all disks via a bundled `smartctl`, shows health/wear/temperature/history, and posts notifications on degradation.

**Architecture:** SwiftPM package with two targets: `DiskHealthCore` (pure logic: models, JSON parsing, health evaluation, alert diffing, history store, smartctl runner — fully unit-tested) and `DiskHealth` (SwiftUI executable: MenuBarExtra UI, scheduler, notifications, settings). `scripts/build-app.sh` assembles `DiskHealth.app` and copies `smartctl` into `Contents/Resources`.

**Tech Stack:** Swift 6.2 (CLT only, no Xcode), SwiftUI, Swift Charts, UserNotifications, ServiceManagement, swift-testing.

**Spec:** `docs/superpowers/specs/2026-11-01-disk-monitor-design.md`

## Global Constraints

- macOS deployment target: 13 (`platforms: [.macOS(.v13)]`), `swift-tools-version:6.0`.
- App name `DiskHealth`, bundle id `com.local.DiskHealth`, `LSUIElement = true`.
- smartctl invocation: list `smartctl --scan-open --json=c`; per-disk `smartctl -x --json=c <name> [-d <type>]`.
- **smartctl exit code is a bitmask; non-zero is NOT a failure.** Parse JSON whenever stdout is valid JSON (real Apple NVMe returns exit 4 with full data). Only bits 0–1 (`exit & 0b11`) mean "no data".
- NVMe data unit = 512 000 bytes.
- Defaults: poll interval 30 min; wear warning 80 %, wear critical 90 %; temperature warning 60 °C.
- History file: `~/Library/Application Support/DiskHealth/history.json`; keep 365 days. Alert state: `alert-state.json` in same dir.
- Each alert fires once per event (dedupe by disk serial + alert kind + threshold).
- No Core Data, no third-party dependencies.
- Tests run only via `scripts/test.sh` (adds `-F/-rpath` to `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`).

## Review Focus

- smartctl exit status ≠ 0 with valid JSON (Apple NVMe, exit 4) → disk must still show full data, not "error". Test in Task 2.
- USB disk with no SMART (JSON without `smart_status`, `smart_support.available == false`) → shown as "SMART недоступний", health `.unknown`, never `.critical`, no alerts. Test in Tasks 2 & 3.
- Missing `user_capacity` (Apple NVMe returns null) → fall back to `nvme_total_capacity` / `nvme_namespaces[0].capacity.bytes`, else show "—"; never crash. Test in Task 2.
- Same disk seen twice over polls (and app relaunch) → no duplicate notification for an unchanged condition; condition clearing then reoccurring fires again. Test in Task 4.
- Bundled `smartctl` missing or not executable → UI shows a clear error banner instead of an empty list. Test in Task 5.

---

### Task 1: Package skeleton, test script, git

**Files:**
- Create: `Package.swift`, `.gitignore`, `scripts/test.sh`, `Sources/DiskHealthCore/DiskHealthCore.swift` (placeholder), `Sources/DiskHealth/main.swift` (placeholder), `Tests/DiskHealthCoreTests/SmokeTests.swift`
- Existing: `Tests/DiskHealthCoreTests/Fixtures/nvme_apple.json` (real `smartctl -x --json=c /dev/disk0` output, exit 4)

**Interfaces:**
- Produces: targets `DiskHealthCore` (library), `DiskHealth` (executable, depends on core), `DiskHealthCoreTests` (resources: `.copy("Fixtures")`).

- [ ] **Step 1:** `git init`, `.gitignore` with `.build/`, `build/`, `*.app`, `.DS_Store`.
- [ ] **Step 2:** Write `Package.swift` per above; `scripts/test.sh`:
  ```bash
  #!/bin/bash
  set -euo pipefail
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  cd "$(dirname "$0")/.."
  swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
  ```
- [ ] **Step 3:** Smoke test `@Test func fixtureLoads()` — `Bundle.module.url(forResource: "nvme_apple", withExtension: "json", subdirectory: "Fixtures")` is non-nil.
- [ ] **Step 4:** Run `scripts/test.sh` → `1 test ... passed`. Run `swift build` → succeeds.
- [ ] **Step 5:** Commit `chore: SwiftPM skeleton with test script`.

### Task 2: Models + smartctl JSON parser

**Files:**
- Create: `Sources/DiskHealthCore/DiskInfo.swift`, `Sources/DiskHealthCore/SmartParser.swift`
- Create fixtures: `Fixtures/sata_ssd.json` (hand-written minimal ATA SSD: `device.type "sat"`, `smart_status.passed true`, `user_capacity.bytes 500107862016`, `temperature.current 35`, `power_on_time.hours 1000`, `power_cycle_count 50`, `ata_smart_attributes.table` with ids 5 raw 0, 197 raw 2, 199 raw 0, 231 value 97 (SSD_Life_Left), 241 raw 2000 (Total_LBAs_Written)), `Fixtures/usb_nosmart.json` (`device.type "scsi"`, `model_name "USB Flash"`, `smart_support {"available": false}`, no `smart_status`), `Fixtures/scan.json` (`{"devices":[{"name":"/dev/disk0","type":"nvme","protocol":"NVMe"},{"name":"/dev/disk4","type":"sat","protocol":"ATA"}]}`)
- Test: `Tests/DiskHealthCoreTests/SmartParserTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ScannedDevice: Codable, Hashable, Sendable { public var name: String; public var type: String; public var proto: String }
  public struct DiskInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String            // serial if present, else device name
    public var deviceName: String     // "/dev/disk0"
    public var deviceType: String     // "nvme" | "sat" | "scsi" ...
    public var model: String
    public var serial: String?
    public var firmware: String?
    public var capacityBytes: Int64?
    public var smartAvailable: Bool
    public var smartPassed: Bool?
    public var criticalWarning: Int?  // NVMe only
    public var wearPercent: Int?      // 0...100+, NVMe percentage_used or 100 - SSD life-left attribute
    public var availableSpare: Int?
    public var temperatureC: Int?
    public var powerOnHours: Int?
    public var powerCycles: Int?
    public var unsafeShutdowns: Int?
    public var bytesWritten: Int64?
    public var bytesRead: Int64?
    public var mediaErrors: Int?      // NVMe media_errors
    public var reallocatedSectors: Int?   // ATA 5
    public var pendingSectors: Int?       // ATA 197
    public var crcErrors: Int?            // ATA 199
    public var messages: [String]         // smartctl.messages[].string
  }
  public enum SmartParser {
    public static func parseScan(_ data: Data) throws -> [ScannedDevice]
    public static func parseDisk(_ data: Data) throws -> DiskInfo
  }
  ```
- Wear for ATA: first present of attrs 231 (life left, use `100 - value`), 233 (`100 - value`), 177 / 202 (`100 - value`). Bytes written ATA: attr 241 raw × 512 only when its name contains "LBAs"; otherwise `nil` (vendor-specific units are out of scope for v1).

- [ ] **Step 1:** Write tests:
  - `nvmeAppleParses`: model `"APPLE SSD AP0512M"`, serial `"S0TESTSERIAL0001"`, `deviceType == "nvme"`, `smartPassed == true`, `criticalWarning == 0`, `wearPercent == 50`, `availableSpare == 100`, `temperatureC == 31`, `powerOnHours == 5516`, `powerCycles == 245`, `unsafeShutdowns == 64`, `mediaErrors == 0`, `bytesWritten == 1183583581 * 512000`, `smartAvailable == true`, `messages.count == 1` (exit-4 case still parses).
  - `nvmeMissingCapacityIsNilNotCrash`: `capacityBytes == nil` for fixture.
  - `sataParses`: `wearPercent == 3`, `pendingSectors == 2`, `reallocatedSectors == 0`, `capacityBytes == 500107862016`, `bytesWritten == 2000 * 512`.
  - `usbNoSmart`: `smartAvailable == false`, `smartPassed == nil`, `wearPercent == nil`, `id == "/dev/disk..."` fallback works.
  - `scanParses`: 2 devices, second `type == "sat"`.
  - `garbageThrows`: `parseDisk(Data("not json".utf8))` throws.
- [ ] **Step 2:** `scripts/test.sh` → FAIL (types not defined).
- [ ] **Step 3:** Implement with private `Decodable` mirror structs of smartctl JSON (all fields optional), mapping into `DiskInfo`.
- [ ] **Step 4:** `scripts/test.sh` → all pass.
- [ ] **Step 5:** Commit `feat(core): parse smartctl JSON into DiskInfo`.

### Task 3: Health evaluation

**Files:**
- Create: `Sources/DiskHealthCore/Health.swift`, `Sources/DiskHealthCore/Thresholds.swift`
- Test: `Tests/DiskHealthCoreTests/HealthTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Thresholds: Codable, Equatable, Sendable {
    public var wearWarning = 80; public var wearCritical = 90; public var temperatureWarning = 60
    public init() {}
  }
  public enum HealthLevel: Int, Codable, Comparable, Sendable { case unknown = 0, ok, warning, critical }
  public struct HealthReport: Equatable, Sendable { public var level: HealthLevel; public var reasons: [String]; public var healthPercent: Int? }
  public enum HealthEvaluator { public static func evaluate(_ d: DiskInfo, _ t: Thresholds) -> HealthReport }
  ```
- `healthPercent = max(0, 100 - wear)`. Reasons are Ukrainian user-facing strings (e.g. `"SMART: FAILED"`, `"Знос 92%"`, `"Температура 65 °C"`, `"Перепризначені сектори: 3"`). `HealthLevel` comparison: overall app level = max over disks, but `.unknown` never outranks `.ok` for icon (treat as ok in aggregate).

- [ ] **Step 1:** Tests: `okDisk` (nvme fixture, wear 50 → `.ok`, healthPercent 50); `wearWarning` (wear 85 → `.warning`); `wearCritical` (90 → `.critical`); `smartFailed` → `.critical`; `criticalWarningNonZero` → `.critical`; `mediaErrors > 0` → `.critical`; `hot` (temp 60) → `.warning`; `pendingSectors 2` → `.warning`; `noSmart` → `.unknown`, reasons contain `"SMART недоступний"`; `customThresholds` (wearWarning 40 → nvme fixture `.warning`).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): health evaluation with thresholds`.

### Task 4: Alert engine (dedupe) + persistence

**Files:**
- Create: `Sources/DiskHealthCore/AlertEngine.swift`
- Test: `Tests/DiskHealthCoreTests/AlertEngineTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Alert: Equatable, Sendable { public var key: String; public var diskID: String; public var title: String; public var body: String; public var critical: Bool }
  public struct AlertState: Codable, Equatable, Sendable {
    public var active: Set<String> = []            // keys currently in alarm
    public var lastCounters: [String: [String: Int]] = [:]  // diskID -> counter name -> value
    public init() {}
  }
  public enum AlertEngine {
    public static func diff(disks: [DiskInfo], thresholds: Thresholds, state: inout AlertState) -> [Alert]
  }
  ```
- Condition keys: `"\(id)|smartFailed"`, `"|criticalWarning"`, `"|wear\(threshold)"` (both 80 and 90 separately), `"|temp"`. Fire when key enters `active`; remove when condition clears (so it can fire again). Counters (`mediaErrors`, `reallocatedSectors`, `pendingSectors`, `crcErrors`): fire when value > previous stored value (first sighting just stores, no alert unless value > 0 for mediaErrors/realloc/pending). Disks with `smartAvailable == false` produce no alerts.

- [ ] **Step 1:** Tests: `firesOnceForWear` (wear 85 twice → 1 alert total); `refiresAfterClear` (85 → 50 → 85 → 2 alerts); `bothWearThresholds` (95 on first poll → 2 alerts, one `critical`); `counterIncreaseFires` (crc 0 → 3 → 1 alert; 3 → 3 → none); `firstSightPendingNonZeroFires`; `noSmartNoAlerts`; `stateRoundTripsJSON` (encode/decode `AlertState` equal).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): alert diffing with dedupe`.

### Task 5: smartctl runner + history store

**Files:**
- Create: `Sources/DiskHealthCore/SmartctlRunner.swift`, `Sources/DiskHealthCore/HistoryStore.swift`
- Test: `Tests/DiskHealthCoreTests/RunnerTests.swift`, `Tests/DiskHealthCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SmartctlError: Error, Equatable { case notFound(String), noData(device: String, exitStatus: Int32), badOutput(String) }
  public struct SmartctlRunner: Sendable {
    public init(executable: URL)
    public static func bundled() -> SmartctlRunner   // Bundle.main.resourceURL/"smartctl", fallback /usr/local/bin/smartctl then /opt/homebrew/bin/smartctl
    public func scan() async throws -> [ScannedDevice]
    public func read(_ dev: ScannedDevice) async throws -> DiskInfo
    public func readAll() async -> (disks: [DiskInfo], errors: [String])
  }
  public struct HistorySample: Codable, Equatable, Sendable { public var date: Date; public var wearPercent: Int?; public var temperatureC: Int?; public var bytesWritten: Int64? }
  public final class HistoryStore: @unchecked Sendable {
    public init(fileURL: URL)
    public func append(_ disks: [DiskInfo], at date: Date)   // one sample per disk; drop samples older than 365 days
    public func samples(for diskID: String) -> [HistorySample]
    public func save() throws; public func load()
  }
  ```
- Run process via `Process` off the main actor; read stdout fully before `waitUntilExit`. Error rule: if stdout decodes → return parsed; else if `exitStatus & 0b11 != 0` → `.noData`; else `.badOutput`. `read` passes `-d <type>` from scan.

- [ ] **Step 1:** Tests: `missingExecutableThrowsNotFound` (`SmartctlRunner(executable: URL(fileURLWithPath: "/nonexistent")).scan()` throws `.notFound`); `fakeExecutableNonZeroExitStillParses` — write a temp shell script that `cat`s `nvme_apple.json` and `exit 4`, `read` returns model `"APPLE SSD AP0512M"`; `fakeExecutableExit2NoJSON` → `.noData(exitStatus: 2)`. History: `appendAndReload` (save, new store, load → 1 sample); `prunesOlderThan365Days`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): smartctl runner and history store`.

### Task 6: App model, scheduler, notifications, settings storage

**Files:**
- Create: `Sources/DiskHealth/AppModel.swift`, `Sources/DiskHealth/Notifier.swift`, `Sources/DiskHealth/Settings.swift`, `Sources/DiskHealth/DiskWatcher.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–5.
- Produces:
  ```swift
  @MainActor final class AppModel: ObservableObject {
    @Published var disks: [DiskInfo]; @Published var reports: [String: HealthReport]
    @Published var errors: [String]; @Published var lastUpdate: Date?; @Published var isRefreshing: Bool
    var overall: HealthLevel { get }
    let history: HistoryStore; let settings: AppSettings
    func refresh() async      // readAll → evaluate → history.append+save → AlertEngine.diff → Notifier.post; persist AlertState
    func start()              // initial refresh + Timer every settings.pollMinutes; restart timer when changed; DiskWatcher triggers refresh
  }
  @MainActor final class AppSettings: ObservableObject { @AppStorage-backed: pollMinutes (default 30), wearWarning 80, wearCritical 90, temperatureWarning 60, notificationsEnabled true; var thresholds: Thresholds; launchAtLogin via SMAppService.mainApp }
  enum Notifier { static func requestAuthorization(); static func post(_ alerts: [Alert]) }  // critical → .timeSensitive interruption level
  final class DiskWatcher { init(onChange: @escaping @Sendable () -> Void) }  // DiskArbitration DARegisterDiskAppearedCallback/Disappeared on whole disks, debounce 5 s
  ```
- `UNUserNotificationCenter` only works inside a bundled `.app`; guard with `Bundle.main.bundleIdentifier != nil`.

- [ ] **Step 1:** Implement the four files.
- [ ] **Step 2:** `swift build` → succeeds with no warnings about Sendable errors (Swift 6 strict concurrency).
- [ ] **Step 3:** Commit `feat(app): model, scheduler, notifications, disk watcher`.

### Task 7: SwiftUI UI

**Files:**
- Create: `Sources/DiskHealth/DiskHealthApp.swift` (replaces `main.swift`), `Sources/DiskHealth/Views/DiskListView.swift`, `Views/DiskCardView.swift`, `Views/DiskDetailView.swift`, `Views/SettingsView.swift`, `Sources/DiskHealth/Format.swift`

**Interfaces:**
- Consumes: `AppModel`, `AppSettings`, `HealthReport`, `HistoryStore.samples(for:)`.
- `@main struct DiskHealthApp: App` with `MenuBarExtra { DiskListView } label: { Image(systemName:) }` `.menuBarExtraStyle(.window)` and `Settings { SettingsView }`. Icon: ok `"internaldrive"`, warning `"exclamationmark.triangle.fill"`, critical `"xmark.octagon.fill"` (rendering mode palette/colored).
- List window (~380×520): header (overall status, last update, refresh button with spinner, settings gear via `SettingsLink`/`NSApp.sendAction(Selector(("showSettingsWindow:")))`, Quit), error banner if `errors` non-empty, cards. Card: model, device name + type, health % gauge, temperature, written TB, status color dot, reasons. Tap card → navigate (NavigationStack) to detail: all `DiskInfo` fields in `Grid`, and Swift Charts line charts for wear % and temperature from history (hide chart when < 2 samples).
- `Format`: bytes → `ByteCountFormatter` decimal; hours → "5516 год (≈ 230 дн)".
- All UI copy in Ukrainian.

- [ ] **Step 1:** Implement views.
- [ ] **Step 2:** `swift build` → succeeds.
- [ ] **Step 3:** Commit `feat(app): menu bar UI, detail charts, settings`.

### Task 8: App bundle script + manual verification

**Files:**
- Create: `scripts/build-app.sh`, `Resources/Info.plist`, `README.md`

**Interfaces:**
- `scripts/build-app.sh [--smartctl PATH]`: `swift build -c release`; create `build/DiskHealth.app/Contents/{MacOS,Resources}`; copy binary and `Info.plist` (`CFBundleIdentifier com.local.DiskHealth`, `CFBundleExecutable DiskHealth`, `LSUIElement true`, `LSMinimumSystemVersion 13.0`, `CFBundleShortVersionString 1.0`); copy smartctl from `--smartctl` or `$(brew --prefix smartmontools)/bin/smartctl` resolved through symlinks (`realpath`) to `Contents/Resources/smartctl`, `chmod 755`; fail loudly if not found; warn if `lipo -archs` of smartctl doesn't include `$(uname -m)`; `codesign --force --deep -s - build/DiskHealth.app`.
- README (Ukrainian): build, run, test commands; note about Apple Silicon needing arm64/universal smartctl; USB SMART limitation.

- [ ] **Step 1:** Write script, plist, README.
- [ ] **Step 2:** Run `scripts/build-app.sh` → `build/DiskHealth.app` exists; `build/DiskHealth.app/Contents/Resources/smartctl --version` prints `smartctl 7.5`.
- [ ] **Step 3:** `open build/DiskHealth.app` → menu-bar icon appears; disk0 card shows APPLE SSD AP0512M, health 50 %, temperature; screenshot to confirm. Set wear warning to 40 in Settings → refresh → warning icon + one notification; refresh again → no second notification.
- [ ] **Step 4:** `scripts/test.sh` → all pass.
- [ ] **Step 5:** Commit `feat: app bundle with embedded smartctl`.
