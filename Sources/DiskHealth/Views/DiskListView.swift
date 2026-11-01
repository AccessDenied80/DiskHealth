import DiskHealthCore
import SwiftUI

struct DiskListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: DiskInfo?

    var body: some View {
        VStack(spacing: 0) {
            if let disk = selected {
                DiskDetailView(disk: disk, report: model.reports[disk.id]) { selected = nil }
            } else {
                header
                Divider()
                content
            }
        }
        .frame(width: 400, height: 540)
        .onChange(of: model.disks) { disks in
            // Оновлюємо відкриті деталі новими даними.
            if let s = selected { selected = disks.first { $0.id == s.id } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(model.overall.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.overall.title).font(.headline)
                Text(updatedText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Оновити зараз")

            Menu {
                Button("Налаштування…") { openSettings() }
                Divider()
                Button("Вийти") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(model.errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.bubble")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                if model.disks.isEmpty && model.errors.isEmpty {
                    Text(model.isRefreshing ? "Опитую диски…" : "Дисків не знайдено")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                ForEach(model.disks) { disk in
                    DiskCardView(disk: disk, report: model.reports[disk.id])
                        .contentShape(Rectangle())
                        .onTapGesture { selected = disk }
                }
            }
            .padding(12)
        }
    }

    private var updatedText: String {
        guard let d = model.lastUpdate else { return "Ще не оновлювалось" }
        return "Оновлено о " + d.formatted(date: .omitted, time: .shortened)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
