import Charts
import DiskHealthCore
import SwiftUI

struct DiskDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    let disk: DiskInfo
    let report: HealthReport?
    let onBack: () -> Void
    /// `false` лише для рендеру в PNG: ImageRenderer не малює вміст ScrollView.
    var scrollable = true

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if scrollable {
                FittedScrollView(maxHeight: 600) { details }
            } else {
                details
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(disk.model).font(.headline).lineLimit(1)
            Spacer()
        }
        .padding(12)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            status
            attributes
            charts
            if settings.showSmartctlMessages && !disk.messages.isEmpty {
                section("smartctl messages") {
                    ForEach(disk.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(12)
    }

    private var status: some View {
        let level = report?.level ?? .unknown
        return HStack {
            Circle().fill(level.color).frame(width: 12, height: 12)
            Text(level.title).font(.title3.bold())
            Spacer()
            if let hp = report?.healthPercent { Text("Health \(hp)%").font(.title3) }
        }
    }

    /// Показуємо лише ті показники, які диск справді віддав.
    private var attributes: some View {
        section("Attributes") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Device", "\(disk.deviceName) (\(disk.deviceType.uppercased()))")
                row("Serial number", disk.serial)
                row("Firmware", disk.firmware)
                row("Capacity", disk.capacityBytes.map { Format.bytes($0) })
                row("SMART", disk.smartAvailable
                    ? (disk.smartPassed == false ? "FAILED" : "PASSED")
                    : String(localized: "unavailable"))
                row("Wear", disk.wearPercent.map { Format.percent($0) })
                row("Available spare", disk.availableSpare.map { Format.percent($0) })
                row("Temperature", disk.temperatureC.map { Format.temperature($0) })
                row("Data written", disk.bytesWritten.map { Format.bytes($0) })
                row("Data read", disk.bytesRead.map { Format.bytes($0) })
                row("Power-on time", disk.powerOnHours.map { Format.hours($0) })
                row("Power cycles", disk.powerCycles.map(String.init))
                row("Unsafe shutdowns", disk.unsafeShutdowns.map(String.init))
                row("Critical warning", disk.criticalWarning.map(String.init))
                row("Media errors", disk.mediaErrors.map(String.init))
                row("Reallocated sectors", disk.reallocatedSectors.map(String.init))
                row("Pending sectors", disk.pendingSectors.map(String.init))
                row("CRC errors", disk.crcErrors.map(String.init))
            }
            .font(.callout)
        }
    }

    /// Графік показуємо, лише коли є хоча б дві точки з даними; диск без температури
    /// й зносу (USB-міст) графіків не має зовсім.
    @ViewBuilder private var charts: some View {
        let samples = model.history.samples(for: disk.id)
        let wear = samples.compactMap { s in s.wearPercent.map { (s.date, $0) } }
        let temps = samples.compactMap { s in s.temperatureC.map { (s.date, $0) } }
        if wear.count >= 2 {
            section("Wear, %") {
                Chart(wear, id: \.0) { LineMark(x: .value("Date", $0.0), y: .value("%", $0.1)) }
                    .frame(height: 110)
            }
        }
        if temps.count >= 2 {
            section("Temperature, °C") {
                Chart(temps, id: \.0) {
                    LineMark(x: .value("Date", $0.0), y: .value("°C", $0.1)).foregroundStyle(.orange)
                }
                .frame(height: 110)
            }
        }
        if wear.count < 2 && temps.count < 2 && (disk.wearPercent != nil || disk.temperatureC != nil) {
            Text("Charts will appear after a few readings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(title).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}
