import AppKit
import os
import PacemarkKit
import SwiftUI

/// Opens the settings window when Pacemark is opened again while it runs
/// (Spotlight, Finder, `open`), which a menu-bar-only app otherwise ignores
/// (§5). This also works with the item hidden in System Settings > Menu Bar.
///
/// Reach it through the `@NSApplicationDelegateAdaptor` property, never via
/// `NSApp.delegate`: that is SwiftUI's own delegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI's action for opening a window. The delegate has no SwiftUI
    /// environment, so the menu bar label hands it over when it appears at
    /// launch.
    var openWindow: OpenWindowAction?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let openWindow else {
            shellLog.error("Pacemark was opened again before the menu bar label appeared: no settings window")
            return false
        }
        openWindow.openSettings()
        return false
    }
}

nonisolated let shellLog = Logger(subsystem: "xyz.chrismetz.pacemark", category: "app")
