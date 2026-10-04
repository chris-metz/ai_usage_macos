import Foundation
import PacemarkKit
import Testing

/// What the menu bar item and the dropdown show (§6.3), with the percentage
/// on, at a fixed `now`.
@Suite struct DisplayTests {
    @Test func beforeTheFirstQueryFinishesBothShowLoading() {
        let state = ProviderState(isQuerying: true)

        let result = display(state, settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .loading,
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")
        ))
    }

    @Test func valuesShowAsRowsAndTheFirstLimitsPercentageInTheMenuBar() {
        let limits = [
            session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
            weekly(utilization: 95, resetsAt: "2026-10-07T01:00:00Z"),
        ]

        let result = display(succeeded(limits, at: now), settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .limits(limits),
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .percentage("71%", isRed: false), accessibilityText: "Session limit 71%")
        ))
    }

    @Test func aProblemShowsItsMessageAndAWarningInTheMenuBar() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .problem(notLoggedIn))

        let result = display(state, settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .problem(notLoggedIn),
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: Not logged in")
        ))
    }

    @Test func aTemporaryErrorBeforeAnyValuesShowsNoValues() {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, failureStreak: 1)

        let result = display(state, settings: Settings(), now: now)

        #expect(result == Display(
            dropdown: .noValues,
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")
        ))
    }

    @Test(arguments: [
        (89.4, "89%", false),
        (89.5, "90%", true),
        (140, "100%", true),
    ])
    func theMenuBarPercentageTurnsRedFromADisplayed90Percent(utilization: Double, text: String, isRed: Bool) {
        let limits = [session(utilization: utilization, resetsAt: "2026-10-04T12:00:00Z")]

        let result = display(succeeded(limits, at: now), settings: Settings(), now: now)

        #expect(result.menuBar == MenuBarDisplay(
            content: .percentage(text, isRed: isRed),
            accessibilityText: "Session limit \(text)"
        ))
    }
}

/// The state after a successful query that finished at `time`.
private func succeeded(_ limits: [Limit], at time: Date) -> ProviderState {
    ProviderState(lastAttemptAt: time, lastOutcome: .success, limits: limits, lastSuccessAt: time)
}
