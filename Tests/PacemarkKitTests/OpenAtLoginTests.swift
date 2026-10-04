import Foundation
import PacemarkKit
import ServiceManagement
import Testing

/// The `Open at Login` switch (§4, §5), backed only by the login item, with
/// a fake standing in for `SMAppService.mainApp`.
@Suite struct OpenAtLoginTests {
    @Test func aCopyOutsideApplicationsNeverReadsTheStatus() {
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: buildCopy)

        openAtLogin.refresh()
        openAtLogin.switchTo(true)
        openAtLogin.switchTo(false)

        #expect(openAtLogin.state == .notInApplications)
        #expect(loginItem.statusReads == 0)
        #expect(loginItem.changes == 0)
    }

    @Test(arguments: [
        "/Users/chris/Applications/Pacemark.app",
        "/Applications/Utilities/Pacemark.app",
        "/Applications/Pacemark copy.app",
        "/Volumes/Backup/Applications/Pacemark.app",
    ])
    func everyOtherCopyIsOutsideApplications(path: String) {
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: URL(filePath: path, directoryHint: .isDirectory))

        openAtLogin.refresh()

        #expect(openAtLogin.state == .notInApplications)
        #expect(loginItem.statusReads == 0)
    }

    @Test(arguments: [
        URL(filePath: "/Applications/Pacemark.app", directoryHint: .isDirectory),
        URL(filePath: "/Applications/Pacemark.app", directoryHint: .notDirectory),
        URL(filePath: "/Applications/Utilities/../Pacemark.app", directoryHint: .isDirectory),
    ])
    func theInstalledCopyIsFoundHoweverItsURLIsSpelled(bundleURL: URL) {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(.enabled), bundleURL: bundleURL)

        openAtLogin.refresh()

        #expect(openAtLogin.state == .on)
    }

    @Test func theInstalledCopyShowsAnEnabledLoginItemAsOn() {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(.enabled), bundleURL: installedCopy)

        openAtLogin.refresh()

        #expect(openAtLogin.state == .on)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, .notFound])
    func theInstalledCopyShowsAnyOtherStatusAsOff(status: SMAppService.Status) {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(status), bundleURL: installedCopy)

        openAtLogin.refresh()

        #expect(openAtLogin.state == .off)
    }

    @Test func aLoginItemTurnedOffInSystemSettingsShowsAsOffWithANote() {
        let openAtLogin = OpenAtLogin(loginItem: FakeLoginItem(.requiresApproval), bundleURL: installedCopy)

        openAtLogin.refresh()

        #expect(openAtLogin.state == .turnedOffInSystemSettings)
        #expect(openAtLogin.isOn == false)
    }

    @Test func switchingOnRegistersTheLoginItem() {
        let loginItem = FakeLoginItem(.notRegistered)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()

        openAtLogin.switchTo(true)

        #expect(loginItem.systemStatus == .enabled)
        #expect(openAtLogin.state == .on)
    }

    @Test func switchingOffUnregistersTheLoginItem() {
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()

        openAtLogin.switchTo(false)

        #expect(loginItem.systemStatus == .notRegistered)
        #expect(openAtLogin.state == .off)
    }

    @Test func aFailedSwitchShowsTheStatusReadAgain() {
        let loginItem = FakeLoginItem(.notRegistered)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()
        // Meanwhile the user turned it on elsewhere, so registering fails.
        loginItem.systemStatus = .enabled
        loginItem.error = CocoaError(.featureUnsupported)

        openAtLogin.switchTo(true)

        #expect(openAtLogin.state == .on)
    }

    @Test func aFailedSwitchOffLeavesTheSwitchOn() {
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()
        loginItem.error = CocoaError(.featureUnsupported)

        openAtLogin.switchTo(false)

        #expect(openAtLogin.state == .on)
    }

    @Test func pacemarkNeverAddsItself() {
        let loginItem = FakeLoginItem(.notRegistered)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)

        openAtLogin.refresh()
        openAtLogin.refresh()

        #expect(loginItem.systemStatus == .notRegistered)
        #expect(openAtLogin.state == .off)
    }

    @Test func readingAgainPicksUpAChangeMadeInSystemSettings() {
        let loginItem = FakeLoginItem(.enabled)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()

        loginItem.systemStatus = .requiresApproval
        openAtLogin.refresh()

        #expect(openAtLogin.state == .turnedOffInSystemSettings)
    }

    @Test func theLinkButtonOpensTheLoginItemsSettings() {
        let loginItem = FakeLoginItem(.requiresApproval)
        let openAtLogin = OpenAtLogin(loginItem: loginItem, bundleURL: installedCopy)
        openAtLogin.refresh()

        openAtLogin.openLoginItemsSettings()

        #expect(loginItem.openedSystemSettings)
    }

    let installedCopy = URL(filePath: "/Applications/Pacemark.app", directoryHint: .isDirectory)
    let buildCopy = URL(filePath: "/Users/chris/code/pacemark/build/Pacemark.app", directoryHint: .isDirectory)
}
