import AppKit

@MainActor
enum MenuBarWindow {
    /// Закриває вікно MenuBarExtra. Найнадійніше — «клікнути» іконку в рядку меню: тоді SwiftUI
    /// оновлює свій стан так само, як при закритті користувачем, і наступний клік знову відкриває вікно.
    static func close() {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = statusButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
        NSApp.keyWindow?.orderOut(nil)
    }

    /// Для перевірки в `--snapshot`: чи знайдено кнопку в рядку меню, через яку працює `close()`.
    static var canClose: Bool {
        NSApp.windows.contains { $0.className.contains("NSStatusBarWindow") && statusButton(in: $0.contentView) != nil }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let found = statusButton(in: sub) { return found }
        }
        return nil
    }
}
