import PacemarkClaude
import PacemarkKit
import SwiftUI

/// The shell: the one place that names a provider. Everything else lives in
/// PacemarkKit.
@main
struct PacemarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel(provider: ClaudeProvider(), settingsStore: SettingsStore(defaults: .standard))
        _model = State(initialValue: model)
        Driver.start(model)
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            MenuBarItemLabel(model: model, delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Window("Pacemark Settings", id: settingsWindowID) {
            SettingsView(model: model, version: versionText(infoDictionary: Bundle.main.infoDictionary ?? [:]))
        }
        // The first launch opens no window.
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }
}

/// The menu bar label. It is a live view from launch on, even with the item
/// hidden, so it hands SwiftUI's `openWindow` to the delegate for reopening.
private struct MenuBarItemLabel: View {
    let model: AppModel
    let delegate: AppDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(model: model)
            .onAppear { delegate.openWindow = openWindow }
    }
}
