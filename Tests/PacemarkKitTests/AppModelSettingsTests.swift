import Foundation
import PacemarkKit
import Testing

/// The settings in the app model (§6.4): read from the store at the start,
/// written through on every change.
@Suite(.timeLimit(.minutes(1)))
struct AppModelSettingsTests {
    @Test func theModelStartsWithTheStoredSettings() {
        let defaults = ThrowawayDefaults()
        let stored = Settings(refreshIntervalMinutes: 10, showPercentage: false, hiddenLimits: ["claude/weekly"])
        SettingsStore(defaults: defaults.defaults).save(stored)

        let model = AppModel(provider: FakeProvider(), settingsStore: SettingsStore(defaults: defaults.defaults))

        #expect(model.settings == stored)
    }

    @Test func aChangedSettingIsWrittenThrough() {
        let defaults = ThrowawayDefaults()
        let model = AppModel(provider: FakeProvider(), settingsStore: SettingsStore(defaults: defaults.defaults))

        model.settings.showPercentage = false
        model.settings.hiddenLimits = ["claude/model:Fable"]

        #expect(SettingsStore(defaults: defaults.defaults).load()
            == Settings(showPercentage: false, hiddenLimits: ["claude/model:Fable"]))
    }

    @Test func anIntervalChangeWhoseNewTimeHasPassedQueriesNow() async {
        var time = launchedAt
        let timer = FakeTimer()
        let defaults = ThrowawayDefaults()
        SettingsStore(defaults: defaults.defaults).save(Settings(refreshIntervalMinutes: 15))
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .limits(claudeLimits)),
                             settingsStore: SettingsStore(defaults: defaults.defaults),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        let first = await timer.armed()

        time += 7 * 60
        model.settings.refreshIntervalMinutes = 5
        let next = await timer.armed()

        #expect(first == 15 * 60)
        #expect(model.state.lastAttemptAt == launchedAt + 7 * 60)
        #expect(next == 5 * 60)
    }

    @Test func aNewIntervalCountsFromTheLastAttempt() async {
        var time = launchedAt
        let timer = FakeTimer()
        let provider = FakeProvider(.limits(claudeLimits))
        let model = AppModel(provider: provider, clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()

        time += 2 * 60
        model.settings.refreshIntervalMinutes = 15
        let next = await timer.armed()

        #expect(next == 13 * 60)
        #expect(provider.fetchCount == 1)
    }

    /// Hours before any reset of `claudeLimits`.
    let launchedAt = Date(timeIntervalSince1970: 1_789_980_000)
}
