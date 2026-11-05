import DiskHealthCore
import SwiftUI

struct DiskCardView: View {
    let disk: DiskInfo
    let report: HealthReport?
    var external: ExternalDisk?

    private var level: HealthLevel { report?.level ?? .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: disk.deviceType == "nvme" ? "memorychip" : "externaldrive")
                    .font(.title2)
                    .foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.model).font(.headline).lineLimit(1)
                    Text("\(disk.deviceName) · \(disk.deviceType.uppercased()) · \(Format.bytes(disk.capacityBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let hp = report?.healthPercent {
                    Gauge(value: Double(hp), in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(hp)%").font(.caption.bold())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(level.color)
                    .scaleEffect(0.8)
                    .frame(width: 44, height: 44)
                }
            }

            if disk.smartAvailable && disk.temperatureC == nil && disk.bytesWritten == nil && disk.powerOnHours == nil {
                Text("SMART \(disk.smartPassed == false ? "FAILED" : "PASSED") · the USB bridge reports no detailed data")
                    .font(.caption).foregroundStyle(.secondary)
            } else if disk.smartAvailable {
                HStack(spacing: 16) {
                    stat("thermometer.medium", Format.temperature(disk.temperatureC))
                    stat("square.and.arrow.down", Format.bytes(disk.bytesWritten))
                    stat("clock", String(localized: "\(Format.number(disk.powerOnHours)) h"))
                }
            }

            if let reasons = report?.reasons, !reasons.isEmpty {
                Text(reasons.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(level == .unknown ? .secondary : level.color)
            }

            if let external {
                Divider()
                ExternalDiskControls(disk: external)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(level.color.opacity(level >= .warning ? 0.6 : 0), lineWidth: 1))
    }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
