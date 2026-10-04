import Foundation
import PacemarkKit
import Testing

/// The settings store over `UserDefaults` (§6.5), each test with a suite of
/// its own.
@Suite struct SettingsStoreTests {
    @Test func everySettingSurvivesARoundTrip() {
        let defaults = ThrowawayDefaults()
        let settings = Settings(
            refreshIntervalMinutes: 15,
            showPercentage: false,
            hiddenLimits: ["claude/weekly", "claude/model:Fable"],
            menuBarLimitID: "claude/model:Fable",
            menuBarLimitTitle: "Fable limit"
        )

        SettingsStore(defaults: defaults.defaults).save(settings)

        #expect(SettingsStore(defaults: defaults.defaults).load() == settings)
    }

    @Test func nothingStoredReadsAsTheDefaults() {
        let defaults = ThrowawayDefaults()

        let settings = SettingsStore(defaults: defaults.defaults).load()

        #expect(settings == Settings(refreshIntervalMinutes: 5, showPercentage: true, hiddenLimits: [],
                                     menuBarLimitID: nil, menuBarLimitTitle: nil))
    }

    @Test(arguments: [7, 0, -5, 20])
    func anIntervalOtherThan5_10Or15ReadsAs5(minutes: Int) {
        let defaults = ThrowawayDefaults()
        defaults.defaults.set(minutes, forKey: "refreshIntervalMinutes")

        #expect(SettingsStore(defaults: defaults.defaults).load().refreshIntervalMinutes == 5)
    }

    @Test(arguments: [5, 10, 15])
    func eachIntervalChoiceReadsBack(minutes: Int) {
        let defaults = ThrowawayDefaults()
        defaults.defaults.set(minutes, forKey: "refreshIntervalMinutes")

        #expect(SettingsStore(defaults: defaults.defaults).load().refreshIntervalMinutes == minutes)
    }

    @Test func valuesOfTheWrongTypeReadAsTheDefaults() {
        let defaults = ThrowawayDefaults()
        defaults.defaults.set("10", forKey: "refreshIntervalMinutes")
        defaults.defaults.set("no", forKey: "showPercentage")
        defaults.defaults.set("claude/weekly", forKey: "hiddenLimits")
        defaults.defaults.set(3, forKey: "menuBarLimitID")
        defaults.defaults.set(["Fable limit"], forKey: "menuBarLimitTitle")

        #expect(SettingsStore(defaults: defaults.defaults).load() == Settings())
    }

    @Test func hiddenLimitsWithAnElementOfTheWrongTypeReadAsNone() {
        let defaults = ThrowawayDefaults()
        defaults.defaults.set(["claude/weekly", 3] as [Any], forKey: "hiddenLimits")

        #expect(SettingsStore(defaults: defaults.defaults).load().hiddenLimits == [])
    }

    @Test func clearingTheMenuBarLimitRemovesItsIDAndTitle() {
        let defaults = ThrowawayDefaults()
        let store = SettingsStore(defaults: defaults.defaults)
        store.save(Settings(menuBarLimitID: "claude/weekly", menuBarLimitTitle: "Weekly limit"))

        store.save(Settings())

        #expect(store.load() == Settings())
    }
}

/// A `UserDefaults` suite with a unique name, removed when the value goes
/// away. Tests never touch the standard suite.
final class ThrowawayDefaults {
    let suiteName = "xyz.chrismetz.pacemark.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
