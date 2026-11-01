import DiskHealthCore
import SwiftUI

struct DiskListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selected: DiskInfo?

    var body: some View {
        VStack(spacing: 0) {
            if let disk = selected {
                DiskDetailView(disk: disk, report: model.reports[disk.id]) { selected = nil }
            } else {
                header
                Divider()
                FittedScrollView(maxHeight: 520) { content }
            }
        }
        .frame(width: 400)
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
                updatedText.font(.caption).foregroundStyle(.secondary)
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
            .help("Refresh now")

            Menu {
                Button("Settings…") { SettingsWindow.show(settings: settings) }
                Divider()
                Button("Quit DiskHealth") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
    }

    /// Вміст без ScrollView — його рендерить і `--snapshot`.
    var content: some View {
        VStack(spacing: 8) {
            ForEach(model.errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
            if model.disks.isEmpty && model.errors.isEmpty {
                Text(model.isRefreshing ? "Reading disks…" : "No disks found")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(model.disks) { disk in
                DiskCardView(disk: disk, report: model.reports[disk.id])
                    .contentShape(Rectangle())
                    .onTapGesture { selected = disk }
            }
        }
        .padding(12)
    }

    private var updatedText: Text {
        guard let d = model.lastUpdate else { return Text("Not updated yet") }
        return Text("Updated at \(d.formatted(date: .omitted, time: .shortened))")
    }
}
