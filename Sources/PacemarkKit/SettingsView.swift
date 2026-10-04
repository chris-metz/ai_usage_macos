import AppKit
import SwiftUI

/// The content of the `Pacemark Settings` window (§4): one page in the
/// grouped style of System Settings. Changes apply at once and go straight
/// into the model, which writes them through.
public struct SettingsView: View {
    @Bindable var model: AppModel
    /// The footer's version line, see `versionText(infoDictionary:)`.
    let version: String

    public init(model: AppModel, version: String) {
        self.model = model
        self.version = version
    }

    public var body: some View {
        Form {
            Section("General") {
                Picker("Refresh every", selection: $model.settings.refreshIntervalMinutes) {
                    ForEach(Settings.refreshIntervalChoices, id: \.self) { minutes in
                        Text(verbatim: "\(minutes) min").tag(minutes)
                    }
                }
            }
            Section {
            } footer: {
                HStack {
                    Text(verbatim: version)
                    Text(verbatim: "·")
                    Link("GitHub", destination: URL(string: "https://github.com/chris-metz/pacemark")!)
                    Spacer()
                    Button("Quit Pacemark") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        // The window hugs the content instead of keeping a default height.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The id of the settings window's `Window` scene.
public let settingsWindowID = "settings"

extension OpenWindowAction {
    /// Opens the settings window, or brings it to the front if it is open,
    /// and activates the app (§5). The activation policy stays `.accessory`,
    /// so no Dock icon appears.
    public func openSettings() {
        self(id: settingsWindowID)
        NSApplication.shared.activate()
    }
}

/// The version line of the settings window's footer (§4):
/// `Version 0.1 (a1b2c3d)`, or `Version 0.1` when the bundle has no commit
/// key.
public nonisolated func versionText(infoDictionary: [String: Any]) -> String {
    let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
    guard let commit = infoDictionary["PacemarkGitCommit"] as? String else {
        return "Version \(version)"
    }
    return "Version \(version) (\(commit))"
}
