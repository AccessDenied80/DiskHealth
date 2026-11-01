import AppKit
import SwiftUI

/// Власне вікно налаштувань: у застосунку без Dock-іконки (LSUIElement) системна сцена
/// `Settings` не відкривається через `showSettingsWindow:` на macOS 14+.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(settings: AppSettings) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView().environmentObject(settings)
            ))
            w.title = "Налаштування DiskHealth"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
