import DiskHealthCore
import SwiftUI

/// Томи зовнішнього диска й кнопка «Розмонтувати» / «Змонтувати».
struct ExternalDiskControls: View {
    @EnvironmentObject private var model: AppModel
    let disk: ExternalDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                status.font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.busyDisks.contains(disk.id) {
                    ProgressView().controlSize(.small)
                } else if disk.isMounted {
                    button("Unmount", symbol: "eject")
                } else if !disk.mountTargets.isEmpty {
                    button("Mount", symbol: "externaldrive.badge.plus")
                }
            }
            if let error = model.mountErrors[disk.id] {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var status: Text {
        if !disk.isMounted { return Text("Unmounted. Safe to disconnect.") }
        let names = disk.volumes.filter { $0.mountPoint != nil }.map(\.name)
        return names.isEmpty ? Text("No volumes") : Text(verbatim: names.joined(separator: " · "))
    }

    private func button(_ title: LocalizedStringKey, symbol: String) -> some View {
        Button {
            Task { await model.toggleMount(disk) }
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Картка зовнішнього диска, для якого немає даних SMART: `smartctl` його не бачить.
struct ExternalDiskCardView: View {
    let disk: ExternalDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "externaldrive")
                    .font(.title2)
                    .foregroundStyle(HealthLevel.unknown.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.volumes.first?.name ?? String(localized: "External disk")).font(.headline).lineLimit(1)
                    Text(verbatim: "/dev/\(disk.id) · \(Format.bytes(disk.sizeBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("SMART unavailable").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            ExternalDiskControls(disk: disk)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
