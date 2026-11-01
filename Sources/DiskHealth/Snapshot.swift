#if DEBUG
import AppKit
import SwiftUI

/// `DiskHealth --snapshot <dir>`: опитує диски, рендерить список, деталі кожного диска й налаштування
/// в PNG і завершується. Лише для перевірки вигляду без доступу до екрана.
/// Мову можна задати як для будь-якого застосунку: `-AppleLanguages '(uk)'`.
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
            await writeWindow(host(DiskListView().environmentObject(model).environmentObject(settings)), "list", dir)
            for (i, disk) in model.disks.enumerated() {
                let detail = DiskDetailView(disk: disk, report: model.reports[disk.id], onBack: {})
                    .frame(width: 400)
                    .environmentObject(model)
                    .environmentObject(settings)
                await writeWindow(host(detail), "detail-\(i)", dir)
            }
            await writeWindow(SettingsWindow.make(settings: settings), "settings", dir)
            exit(0)
        }
    }

    @MainActor
    private static func host(_ view: some View) -> NSWindow {
        // Вікно поза екраном не малює власного фону, тож додаємо його явно.
        let hosting = NSHostingController(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.sizingOptions = [.preferredContentSize]
        return NSWindow(contentViewController: hosting)
    }

    /// Рендер справжнього вікна AppKit — так видно Form, ScrollView і контроли, які ImageRenderer не малює.
    /// Кілька проходів макета: FittedScrollView дізнається висоту вмісту лише після першого.
    @MainActor
    private static func writeWindow(_ window: NSWindow, _ name: String, _ dir: URL) async {
        guard let view = window.contentView else { return }
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            if let fitting = window.contentViewController?.view.fittingSize, fitting.height > 1 {
                window.setContentSize(fitting)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        view.layoutSubtreeIfNeeded()
        NSLog("DiskHealth snapshot %@: window content size %@", name, String(describing: view.bounds.size))
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
