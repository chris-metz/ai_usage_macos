import Foundation
import PacemarkKit
import ServiceManagement
import SwiftUI
import Testing

/// The settings window (§4), rendered in light and dark.
@Suite struct SettingsViewTests {
    /// The defaults, after a query delivered the three Claude limits.
    @Test func settingsWindowDefault() async {
        let model = await model(after: .limits(claudeLimits))

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    /// No query has finished yet, and nothing is stored.
    @Test func settingsWindowBeforeFirstSuccess() {
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

    /// The stored menu bar limit is missing from the current limits, and
    /// the weekly limit is hidden in the dropdown.
    @Test func settingsWindowNotAvailable() async {
        let settings = PacemarkKit.Settings(hiddenLimits: ["fake/weekly"], menuBarLimitID: "fake/model:Opus",
                                            menuBarLimitTitle: "Opus limit")
        let model = await model(after: .limits(claudeLimits), settings: settings)

        expectViewSnapshot(settingsView(model, openAtLogin: installedCopy(.notRegistered)), width: 440)
    }

    // The Limit picker.

    @Test func theLimitPickerOffersTheCurrentLimitsInProviderOrderAndSelectsTheFirstWithNothingStored() {
        let picker = menuBarLimitPicker(limits: claudeLimits, providerID: "claude", settings: PacemarkKit.Settings())

        #expect(picker == MenuBarLimitPicker(
            entries: [
                .init(id: "claude/session", title: "Session limit"),
                .init(id: "claude/weekly", title: "Weekly limit"),
                .init(id: "claude/model:Fable", title: "Fable limit"),
            ],
            selection: "claude/session",
            isDisabled: false
        ))
    }

    @Test func theLimitPickerSelectsTheStoredChoice() {
        let settings = PacemarkKit.Settings(menuBarLimitID: "claude/model:Fable", menuBarLimitTitle: "Fable limit")

        let picker = menuBarLimitPicker(limits: claudeLimits, providerID: "claude", settings: settings)

        #expect(picker.selection == "claude/model:Fable")
        #expect(picker.entries.count == 3)
    }

    @Test func aStoredChoiceMissingFromTheCurrentLimitsShowsAsNotAvailable() {
        let settings = PacemarkKit.Settings(menuBarLimitID: "claude/model:Opus", menuBarLimitTitle: "Opus limit")

        let picker = menuBarLimitPicker(limits: claudeLimits, providerID: "claude", settings: settings)

        #expect(picker.entries.last == .init(id: "claude/model:Opus", title: "Opus limit (not available)"))
        #expect(picker.entries.count == 4)
        #expect(picker.selection == "claude/model:Opus")
        #expect(!picker.isDisabled)
    }

    @Test(arguments: [("Weekly limit", "Weekly limit"), (nil, "—")] as [(String?, String)])
    func withoutValuesTheLimitPickerIsDisabledAndShowsTheStoredTitle(storedTitle: String?, shown: String) {
        let settings = PacemarkKit.Settings(menuBarLimitID: storedTitle.map { _ in "claude/weekly" },
                                            menuBarLimitTitle: storedTitle)

        let picker = menuBarLimitPicker(limits: nil, providerID: "claude", settings: settings)

        #expect(picker.isDisabled)
        #expect(picker.entries.map(\.title) == [shown])
        #expect(picker.selection == picker.entries.first?.id)
    }

    @Test func theVersionLineNamesTheCommit() {
        let info = ["CFBundleShortVersionString": "0.1", "PacemarkGitCommit": "a1b2c3d"]

        #expect(versionText(infoDictionary: info) == "Version 0.1 (a1b2c3d)")
    }

    @Test func withoutACommitKeyTheVersionLineHasOnlyTheVersion() {
        let info = ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "42"]

        #expect(versionText(infoDictionary: info) == "Version 0.1")
    }

    /// A model with `settings` after its first query answered `result`.
    private func model(after result: FetchResult, settings: PacemarkKit.Settings = PacemarkKit.Settings()) async -> AppModel {
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(result), clock: { beforeTheResets },
                             sleep: { try await timer.sleep($0) })
        model.settings = settings
        model.launch()
        _ = await timer.armed()
        return model
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
