import Charts
import DiskHealthCore
import SwiftUI

struct DiskDetailView: View {
    @EnvironmentObject private var model: AppModel
    let disk: DiskInfo
    let report: HealthReport?
    let onBack: () -> Void
    /// `false` лише для рендеру в PNG: ImageRenderer не малює вміст ScrollView.
    var scrollable = true

    var body: some View {
        if scrollable {
            VStack(spacing: 0) {
                topBar
                Divider()
                ScrollView { details }
            }
        } else {
            VStack(spacing: 0) {
                topBar
                Divider()
                details
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) { Label("Назад", systemImage: "chevron.left") }
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
            if !disk.messages.isEmpty {
                section("Повідомлення smartctl") {
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
            if let hp = report?.healthPercent { Text("Здоров'я \(hp)%").font(.title3) }
        }
    }

    private var attributes: some View {
        section("Показники") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Пристрій", "\(disk.deviceName) (\(disk.deviceType.uppercased()))")
                row("Серійний номер", disk.serial ?? "—")
                row("Прошивка", disk.firmware ?? "—")
                row("Обсяг", Format.bytes(disk.capacityBytes))
                row("SMART", disk.smartAvailable ? (disk.smartPassed == false ? "FAILED" : "PASSED") : "недоступний")
                if disk.smartAvailable {
                    row("Знос", Format.percent(disk.wearPercent))
                    row("Резерв", Format.percent(disk.availableSpare))
                    row("Температура", Format.temperature(disk.temperatureC))
                    row("Записано", Format.bytes(disk.bytesWritten))
                    row("Прочитано", Format.bytes(disk.bytesRead))
                    row("Час роботи", Format.hours(disk.powerOnHours))
                    row("Увімкнень", Format.number(disk.powerCycles))
                    row("Аварійні вимкнення", Format.number(disk.unsafeShutdowns))
                    row("Critical warning", Format.number(disk.criticalWarning))
                    row("Помилки носія", Format.number(disk.mediaErrors))
                    row("Перепризначені сектори", Format.number(disk.reallocatedSectors))
                    row("Нестабільні сектори", Format.number(disk.pendingSectors))
                    row("Помилки CRC", Format.number(disk.crcErrors))
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder private var charts: some View {
        let samples = model.history.samples(for: disk.id)
        if samples.count >= 2 {
            section("Знос, %") {
                Chart(samples, id: \.date) { s in
                    if let w = s.wearPercent {
                        LineMark(x: .value("Дата", s.date), y: .value("Знос", w))
                    }
                }
                .frame(height: 110)
            }
            section("Температура, °C") {
                Chart(samples, id: \.date) { s in
                    if let t = s.temperatureC {
                        LineMark(x: .value("Дата", s.date), y: .value("°C", t))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(height: 110)
            }
        } else {
            Text("Графіки з'являться після кількох опитувань.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}
