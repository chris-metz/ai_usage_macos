import AppKit
import SwiftUI

/// The content of the `Pacemark Settings` window (§4): one page in the
/// grouped style of System Settings. Changes apply at once and go straight
/// into the model, which writes them through.
public struct SettingsView: View {
    @Bindable var model: AppModel
    let openAtLogin: OpenAtLogin
    /// The footer's version line, see `versionText(infoDictionary:)`.
    let version: String

    public init(model: AppModel, openAtLogin: OpenAtLogin, version: String) {
        self.model = model
        self.openAtLogin = openAtLogin
        self.version = version
    }

    public var body: some View {
        Form {
            Section("General") {
                OpenAtLoginRow(openAtLogin: openAtLogin)
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

/// The `Open at Login` switch with its note (§4). The status is read again
/// when the window appears and when the app becomes active, since the user
/// may have changed it in System Settings.
private struct OpenAtLoginRow: View {
    let openAtLogin: OpenAtLogin

    var body: some View {
        Toggle(isOn: Binding(get: { openAtLogin.isOn }, set: { openAtLogin.switchTo($0) })) {
            Text("Open at Login")
            switch openAtLogin.state {
            case .on, .off:
                EmptyView()
            case .turnedOffInSystemSettings:
                Text("Turned off in System Settings.")
                Button("Open Login Items Settings") {
                    openAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.link)
            case .notInApplications:
                Text("Move Pacemark to Applications to use this.")
            }
        }
        .toggleStyle(.switch)
        .disabled(openAtLogin.state == .notInApplications)
        .onAppear { openAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            openAtLogin.refresh()
        }
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
