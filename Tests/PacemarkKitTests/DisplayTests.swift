import Foundation
import PacemarkKit
import Testing

/// What the menu bar item and the dropdown show (§6.3), with the percentage
/// on, at a fixed `now`.
@Suite struct DisplayTests {
    @Test func beforeTheFirstQueryFinishesBothShowLoading() {
        let state = ProviderState(isQuerying: true)

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .loading,
            updateLine: nil,
            menuBar: MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
        ))
    }

    @Test func valuesShowAsRowsWithTheirAgeAndTheFirstLimitsPercentageInTheMenuBar() {
        let limits = [
            session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
            weekly(utilization: 95, resetsAt: "2026-10-07T01:00:00Z"),
        ]

        let result = display(succeeded(limits, at: now), providerID: "claude", settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .limits(limits),
            updateLine: "Updated just now",
            menuBar: MenuBarDisplay(content: .percentage("71%", isRed: false, isDimmed: false), accessibilityText: "Session limit 71%")
        ))
    }

    @Test func aProblemShowsItsMessageAndAWarningInTheMenuBar() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .problem(notLoggedIn))

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .problem(notLoggedIn),
            updateLine: nil,
            menuBar: MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: Not logged in")
        ))
    }

    @Test func aTemporaryErrorBeforeAnyValuesShowsNoValues() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, failureStreak: 1)

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .noValues,
            updateLine: nil,
            menuBar: MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
        ))
    }

    @Test(arguments: [
        (89.4, "89%", false),
        (89.5, "90%", true),
        (140, "100%", true),
    ])
    func theMenuBarPercentageTurnsRedFromADisplayed90Percent(utilization: Double, text: String, isRed: Bool) {
        let limits = [session(utilization: utilization, resetsAt: "2026-10-04T12:00:00Z")]

        let result = display(succeeded(limits, at: now), providerID: "claude", settings: Settings(), now: now)

        #expect(result.menuBar == MenuBarDisplay(
            content: .percentage(text, isRed: isRed, isDimmed: false),
            accessibilityText: "Session limit \(text)"
        ))
    }

    @Test(arguments: [5, 10, 15], [(-1, false), (0, false), (1, true)])
    func valuesTurnStaleMoreThanTwoIntervalsAfterTheLastSuccess(minutes: Int, offset: (seconds: Int, isStale: Bool)) {
        let age = TimeInterval(2 * minutes * 60 + offset.seconds)
        let state = failed(after: [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")], age: age)

        let result = display(state, providerID: "claude", settings: Settings(refreshIntervalMinutes: minutes), now: now)

        #expect(result.menuBar.content == .percentage("71%", isRed: false, isDimmed: offset.isStale))
        #expect(result.updateLine?.hasPrefix("Couldn't update") == offset.isStale)
    }

    @Test func valuesFromALongRunningQueryAreNotStale() {
        let lastSuccess = now.addingTimeInterval(-30 * 60)
        var state = succeeded([session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")], at: lastSuccess)
        state.isQuerying = true

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result.updateLine == "Updated 30 min ago")
        #expect(result.menuBar.content == .percentage("71%", isRed: false, isDimmed: false))
    }

    @Test func aMenuBarLimitWithNoWindowShows0Percent() {
        let limits = [Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)]

        let result = display(succeeded(limits, at: now), providerID: "claude", settings: Settings(), now: now)

        #expect(result.menuBar == MenuBarDisplay(
            content: .percentage("0%", isRed: false, isDimmed: false),
            accessibilityText: "Session limit 0%"
        ))
    }

    @Test func staleValuesKeepTheirRowsAndSaySoInTheFooterAndTheMenuBar() {
        let limits = [
            session(utilization: 91, resetsAt: "2026-10-04T12:00:00Z"),
            weekly(utilization: 36, resetsAt: "2026-10-07T01:00:00Z"),
        ]

        let result = display(failed(after: limits, age: 23 * 60), providerID: "claude", settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .limits(limits),
            updateLine: "Couldn't update · Last update 23 min ago",
            menuBar: MenuBarDisplay(
                content: .percentage("91%", isRed: true, isDimmed: true),
                accessibilityText: "Session limit 91%, not up to date"
            )
        ))
    }

    @Test func withThePercentageOffTheGlyphCarriesRedAndDimmingAndTheTextStillNamesTheLimit() {
        let at71 = [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")]
        let at91 = [session(utilization: 91, resetsAt: "2026-10-04T12:00:00Z")]
        // The rows of §2 States, in order.
        let rows: [(ProviderState, MenuBarDisplay)] = [
            (ProviderState(isQuerying: true),
             MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")),
            (ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, failureStreak: 1),
             MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")),
            (ProviderState(lastAttemptAt: now, lastOutcome: .problem(notLoggedIn)),
             MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: Not logged in")),
            (succeeded(at71, at: now),
             MenuBarDisplay(content: .glyph(isRed: false, isDimmed: false), accessibilityText: "Session limit 71%")),
            (succeeded(at91, at: now),
             MenuBarDisplay(content: .glyph(isRed: true, isDimmed: false), accessibilityText: "Session limit 91%")),
            (failed(after: at71, age: 23 * 60),
             MenuBarDisplay(content: .glyph(isRed: false, isDimmed: true),
                            accessibilityText: "Session limit 71%, not up to date")),
            (failed(after: at91, age: 23 * 60),
             MenuBarDisplay(content: .glyph(isRed: true, isDimmed: true),
                            accessibilityText: "Session limit 91%, not up to date")),
        ]

        for (state, menuBar) in rows {
            #expect(display(state, providerID: "claude", settings: Settings(showPercentage: false), now: now).menuBar == menuBar)
        }
    }

    @Test func withThePercentageOffAMenuBarLimitWithNoWindowShowsThePlainGlyph() {
        let limits = [Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)]

        let result = display(succeeded(limits, at: now), providerID: "claude", settings: Settings(showPercentage: false), now: now)

        #expect(result.menuBar == MenuBarDisplay(content: .glyph(), accessibilityText: "Session limit 0%"))
    }

    @Test func theMenuBarShowsThePickedLimit() {
        let settings = Settings(menuBarLimitID: "claude/weekly", menuBarLimitTitle: "Weekly limit")

        let result = display(succeeded(threeLimits, at: now), providerID: "claude", settings: settings, now: now)

        #expect(result.menuBar == MenuBarDisplay(
            content: .percentage("36%", isRed: false, isDimmed: false),
            accessibilityText: "Weekly limit 36%"
        ))
    }

    @Test(arguments: ["claude/model:Opus", "other/weekly"])
    func aPickedLimitMissingFromTheValuesFallsBackToTheFirstLimit(menuBarLimitID: String) {
        let settings = Settings(menuBarLimitID: menuBarLimitID, menuBarLimitTitle: "Opus limit")

        let result = display(succeeded(threeLimits, at: now), providerID: "claude", settings: settings, now: now)

        #expect(result.menuBar == MenuBarDisplay(
            content: .percentage("71%", isRed: false, isDimmed: false),
            accessibilityText: "Session limit 71%"
        ))
    }

    @Test func theDropdownLeavesOutHiddenLimitsAndKeepsTheProviderOrder() {
        let settings = Settings(hiddenLimits: ["claude/weekly", "claude/model:Opus"])

        let result = display(succeeded(threeLimits, at: now), providerID: "claude", settings: settings, now: now)

        #expect(result.dropdown == .limits([threeLimits[0], threeLimits[2]]))
    }

    @Test func withEveryLimitHiddenTheDropdownSaysSoAndStillShowsTheStaleLine() {
        let settings = Settings(hiddenLimits: ["claude/session", "claude/weekly", "claude/model:Fable"])

        let result = display(failed(after: threeLimits, age: 23 * 60), providerID: "claude", settings: settings, now: now)

        #expect(result == Display(
            dropdown: .allHidden,
            updateLine: "Couldn't update · Last update 23 min ago",
            menuBar: MenuBarDisplay(
                content: .percentage("71%", isRed: false, isDimmed: true),
                accessibilityText: "Session limit 71%, not up to date"
            )
        ))
    }

    @Test func aMenuBarLimitHiddenInTheDropdownStillShowsInTheMenuBar() {
        let settings = Settings(hiddenLimits: ["claude/model:Fable"], menuBarLimitID: "claude/model:Fable",
                                menuBarLimitTitle: "Fable limit")

        let result = display(succeeded(threeLimits, at: now), providerID: "claude", settings: settings, now: now)

        #expect(result == Display(
            dropdown: .limits([threeLimits[0], threeLimits[1]]),
            updateLine: "Updated just now",
            menuBar: MenuBarDisplay(
                content: .percentage("92%", isRed: true, isDimmed: false),
                accessibilityText: "Fable limit 92%"
            )
        ))
    }

    /// Ages in seconds and how the stale line says them.
    nonisolated static let ages: [(Int, String)] = [
        (10 * 60 + 1, "10 min"),
        (59 * 60 + 59, "59 min"),
        (60 * 60, "1 hr"),
        (2 * 3600 - 1, "1 hr"),
        (24 * 3600 - 1, "23 hr"),
        (24 * 3600, "1 day"),
        (48 * 3600 - 1, "1 day"),
        (48 * 3600, "2 days"),
        (10 * 86400 - 1, "9 days"),
    ]

    @Test(arguments: ages)
    func theStaleLineSaysHowOldTheValuesAreRoundedDown(age: Int, text: String) {
        let state = failed(after: [session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")], age: TimeInterval(age))

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result.updateLine == "Couldn't update · Last update \(text) ago")
    }

    /// Ages in seconds and how the update line says them while the values
    /// aren't stale.
    nonisolated static let updatedAges: [(Int, String)] = [
        (0, "Updated just now"),
        (59, "Updated just now"),
        (60, "Updated 1 min ago"),
        (59 * 60 + 59, "Updated 59 min ago"),
        (60 * 60, "Updated 1 hr ago"),
        (24 * 3600, "Updated 1 day ago"),
        (48 * 3600, "Updated 2 days ago"),
    ]

    @Test(arguments: updatedAges)
    func valuesThatAreNotStaleSayHowOldTheyAreRoundedDown(age: Int, text: String) {
        let lastSuccess = now.addingTimeInterval(-TimeInterval(age))
        let state = succeeded([session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")], at: lastSuccess)

        let result = display(state, providerID: "claude", settings: Settings(), now: now)

        #expect(result.updateLine == text)
    }
}

/// The state after a temporary error at `now`, with values from a success
/// `age` seconds earlier.
func failed(after limits: [Limit], age: TimeInterval) -> ProviderState {
    ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, limits: limits,
                  lastSuccessAt: now.addingTimeInterval(-age), failureStreak: 3)
}

/// The state after a successful query that finished at `time`.
func succeeded(_ limits: [Limit], at time: Date) -> ProviderState {
    ProviderState(lastAttemptAt: time, lastOutcome: .success, limits: limits, lastSuccessAt: time)
}

/// Session 71%, weekly 36%, Fable 92%, as the Claude provider delivers them.
private let threeLimits = [
    session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
    weekly(utilization: 36, resetsAt: "2026-10-07T01:00:00Z"),
    fable(utilization: 92, resetsAt: "2026-10-07T01:00:00Z"),
]
