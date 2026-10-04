import Foundation
import PacemarkKit
import SwiftUI
import Testing

/// The settings window (§4), rendered in light and dark.
@Suite struct SettingsViewTests {
    @Test func settingsWindowDefault() {
        let model = AppModel(provider: FakeProvider())

        expectViewSnapshot(SettingsView(model: model, version: "Version 0.1 (a1b2c3d)"), width: 440)
    }

    @Test func theVersionLineNamesTheCommit() {
        let info = ["CFBundleShortVersionString": "0.1", "PacemarkGitCommit": "a1b2c3d"]

        #expect(versionText(infoDictionary: info) == "Version 0.1 (a1b2c3d)")
    }

    @Test func withoutACommitKeyTheVersionLineHasOnlyTheVersion() {
        let info = ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "42"]

        #expect(versionText(infoDictionary: info) == "Version 0.1")
    }
}
