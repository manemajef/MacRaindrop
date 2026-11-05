import AppKit

/// Keeps the app running after its last window closes, as a background app with no Dock icon,
/// so the Quick Search hotkey keeps working. Opening a window brings the Dock icon back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // A closing window is still on screen while `willClose` is delivered.
                Task { @MainActor in Self.updateActivationPolicy() }
            })
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Windows that warrant a Dock icon: the library and Settings, not the Quick Search panel.
    private static var hasAppWindow: Bool {
        NSApp.windows.contains { window in
            !(window is NSPanel) && window.canBecomeMain && (window.isVisible || window.isMiniaturized)
        }
    }

    private static func updateActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = hasAppWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        // Turning back into a regular app doesn't bring the menu bar forward on its own.
        if wanted == .regular { NSApp.activate() }
    }

    /// Brings a library window forward, opening a new one if every window was closed.
    static func showMainWindow() {
        if hasAppWindow {
            NSApp.activate()
        } else {
            // Relaunching a running app delivers a reopen event, and SwiftUI answers it with a new window.
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        }
    }
}
