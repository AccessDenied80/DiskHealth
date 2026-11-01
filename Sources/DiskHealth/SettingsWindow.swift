import AppKit
import SwiftUI

/// Власне вікно налаштувань: у застосунку без Dock-іконки (LSUIElement) системна сцена
/// `Settings` не відкривається через `showSettingsWindow:` на macOS 14+.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(settings: AppSettings) {
        if window == nil { window = make(settings: settings) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func make(settings: AppSettings) -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView().environmentObject(settings))
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.title = "Налаштування DiskHealth"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        // Без явного розміру вікно з'являється 1×0, доки SwiftUI не перерахує макет.
        w.setContentSize(hosting.view.fittingSize)
        w.center()
        return w
    }
}
