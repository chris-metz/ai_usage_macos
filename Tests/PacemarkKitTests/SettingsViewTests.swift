import Foundation
import PacemarkKit
import ServiceManagement
import SwiftUI
import Testing

/// The settings window (§4), rendered in light and dark.
@Suite struct SettingsViewTests {
    @Test func settingsWindowDefault() {
        let model = AppModel(provider: FakeProvider())

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    @Test func settingsWindowOpenAtLoginTurnedOffInSystemSettings() {
        let model = AppModel(provider: FakeProvider())

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.requiresApproval)), width: 440)
    }

    @Test func settingsWindowOutsideApplications() {
        let model = AppModel(provider: FakeProvider())
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: URL(filePath: "/Users/chris/code/pacemark/build/Pacemark.app"))
        openAtLogin.refresh()

        expectViewSnapshot(settingsView(model, openAtLogin: openAtLogin), width: 440)

        #expect(loginItem.statusReads == 0)
    }

    @Test func theVersionLineNamesTheCommit() {
        let info = ["CFBundleShortVersionString": "0.1", "PacemarkGitCommit": "a1b2c3d"]

        #expect(versionText(infoDictionary: info) == "Version 0.1 (a1b2c3d)")
    }

    @Test func withoutACommitKeyTheVersionLineHasOnlyTheVersion() {
        let info = ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "42"]

        #expect(versionText(infoDictionary: info) == "Version 0.1")
    }

    private func settingsView(_ model: AppModel, openAtLogin: OpenAtLogin) -> SettingsView {
        SettingsView(model: model, openAtLogin: openAtLogin, version: "Version 0.1 (a1b2c3d)")
    }

    /// The copy at `/Applications/Pacemark.app`, its login item's status
    /// read as the window would on appearing.
    private func installedCopy(_ status: SMAppService.Status) -> OpenAtLogin {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(status), bundleURL: URL(filePath: "/Applications/Pacemark.app"))
        openAtLogin.refresh()
        return openAtLogin
    }
}
