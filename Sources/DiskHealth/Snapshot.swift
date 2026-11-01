#if DEBUG
import AppKit
import SwiftUI

/// `DiskHealth --snapshot <dir>`: опитує диски, рендерить список і деталі першого диска в PNG і завершується.
/// Лише для перевірки вигляду без доступу до екрана.
enum Snapshot {
    static var outputDir: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    @MainActor
    static func run(model: AppModel, settings: AppSettings, to dir: URL) {
        Task { @MainActor in
            await model.refresh()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            write(
                VStack(spacing: 8) {
                    ForEach(model.disks) { DiskCardView(disk: $0, report: model.reports[$0.id]) }
                }
                .padding(12)
                .frame(width: 400),
                "list", dir
            )
            if let disk = model.disks.first {
                write(
                    DiskDetailView(disk: disk, report: model.reports[disk.id], onBack: {}, scrollable: false)
                        .frame(width: 400)
                        .environmentObject(model),
                    "detail", dir
                )
            }
            writeWindow(SettingsWindow.make(settings: settings), "settings", dir)
            exit(0)
        }
    }

    /// Рендер справжнього вікна AppKit — так видно Form і контроли, які ImageRenderer не малює.
    @MainActor
    private static func writeWindow(_ window: NSWindow, _ name: String, _ dir: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        NSLog("DiskHealth snapshot \(name): window content size \(view.bounds.size)")
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private static func write(_ view: some View, _ name: String, _ dir: URL) {
        let renderer = ImageRenderer(content: view.background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
