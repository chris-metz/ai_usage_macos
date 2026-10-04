import Foundation
import PacemarkKit
import Testing

/// The pace and limit display (§6.1), at a fixed `now` in Berlin.
@Suite struct LimitDisplayTests {
    @Test func aSessionLimitAboveItsPaceIsOverPace() {
        // Window 09:00–14:00 Berlin, now 12:08: 188 of 300 min elapsed.
        let limit = session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display == LimitDisplay(
            title: "Session limit",
            state: .overPace,
            displayedUtilization: 71,
            percentText: "71%",
            fillFraction: 0.71,
            fillColor: .orange,
            paceMarker: 188.0 / 300.0,
            resetLine: "Resets in 1 hr 52 min",
            paceText: "8% over pace",
            paceTextColor: .orange,
            accessibilityText: "Session limit, 71%, 8% over pace, resets in 1 hr 52 min"
        ))
    }

    @Test func theAccessibilityTextReadsTheWeekdayFormInLowerCase() {
        let limit = weekly(utilization: 63, resetsAt: "2026-10-07T01:00:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.accessibilityText == "Weekly limit, 63%, On pace, resets Wed 03:00")
    }

    @Test func aLimitAtItsPaceIsOnPace() {
        // 9000 of 18000 s elapsed: pace 50.
        let limit = session(utilization: 50, resetsAt: "2026-10-04T12:38:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.state == .onPace)
        #expect(display.fillColor == .blue)
        #expect(display.paceText == "On pace")
        #expect(display.paceTextColor == .secondary)
        #expect(display.accessibilityText == "Session limit, 50%, On pace, resets in 2 hr 30 min")
    }

    @Test func aLimitBelowItsPaceIsUnderPace() {
        let limit = session(utilization: 46, resetsAt: "2026-10-04T12:38:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.state == .underPace)
        #expect(display.fillColor == .blue)
        #expect(display.paceText == "4% under pace")
        #expect(display.paceTextColor == .green)
    }

    @Test func aLimitFrom90PercentIsHighWithARedBarAndThePaceTextOfItsDeviation() {
        // Pace 50.
        let overPace = limitDisplay(session(utilization: 92, resetsAt: "2026-10-04T12:38:00Z"),
                                    now: now, timeZone: berlin, locale: enDE)
        // Pace 90.
        let onPace = limitDisplay(session(utilization: 90, resetsAt: "2026-10-04T10:38:00Z"),
                                  now: now, timeZone: berlin, locale: enDE)
        // Pace 99.9.
        let underPace = limitDisplay(session(utilization: 90, resetsAt: "2026-10-04T10:08:18Z"),
                                     now: now, timeZone: berlin, locale: enDE)

        for display in [overPace, onPace, underPace] {
            #expect(display.state == .high)
            #expect(display.fillColor == .red)
        }
        #expect(overPace.paceText == "42% over pace")
        #expect(overPace.paceTextColor == .orange)
        #expect(onPace.paceText == "On pace")
        #expect(onPace.paceTextColor == .secondary)
        #expect(underPace.paceText == "10% under pace")
        #expect(underPace.paceTextColor == .green)
    }

    @Test func aLimitAt100PercentIsExhausted() {
        let limit = session(utilization: 100, resetsAt: "2026-10-04T12:38:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.state == .exhausted)
        #expect(display.fillFraction == 1)
        #expect(display.fillColor == .red)
        #expect(display.paceMarker == 0.5)
        #expect(display.paceText == "Limit reached")
        #expect(display.paceTextColor == .red)
        #expect(display.accessibilityText == "Session limit, 100%, Limit reached, resets in 2 hr 30 min")
    }

    @Test(arguments: [
        (50.5, "1% over pace"),
        (49.5, "1% under pace"),
        (50.49, "On pace"),
        (49.51, "On pace"),
    ])
    func theDeviationRoundsHalvesAwayFromZero(utilization: Double, paceText: String) {
        // Pace 50.
        let limit = session(utilization: utilization, resetsAt: "2026-10-04T12:38:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.paceText == paceText)
    }

    @Test(arguments: [
        (89.4, LimitState.underPace, "89%"),
        (89.5, LimitState.high, "90%"),
        (99.4, LimitState.high, "99%"),
        (99.5, LimitState.exhausted, "100%"),
        (140, LimitState.exhausted, "100%"),
        (-3, LimitState.underPace, "0%"),
    ])
    func theStateFollowsTheDisplayedUtilization(utilization: Double, state: LimitState, percentText: String) {
        // Pace 99.9, so none of them is over pace.
        let limit = session(utilization: utilization, resetsAt: "2026-10-04T10:08:18Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.state == state)
        #expect(display.percentText == percentText)
    }

    @Test func aServerValueAbove100FillsTheBar() {
        let limit = session(utilization: 140, resetsAt: "2026-10-04T12:38:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.displayedUtilization == 100)
        #expect(display.fillFraction == 1)
    }

    @Test func atTheWindowStartThePaceIs0() {
        // The window began exactly 5 h before its reset time, i.e. now.
        let limit = session(utilization: 0, resetsAt: "2026-10-04T15:08:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.paceMarker == 0)
        #expect(display.state == .onPace)
    }

    @Test func aResetTimeMoreThanAWindowAwayClampsThePaceTo0() {
        let limit = session(utilization: 0, resetsAt: "2026-10-04T16:08:00Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.paceMarker == 0)
    }

    @Test func atTheWindowEndThePaceIs100() {
        // 1 ms before the reset time.
        let limit = weekly(utilization: 100, resetsAt: "2026-10-04T10:08:00.001Z")

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.paceMarker.map { ($0 * 100).rounded() } == 100)
        #expect(display.state == .exhausted)
    }

    @Test func aLimitWithoutAWindowHasNoWindow() {
        let limit = Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display == LimitDisplay(
            title: "Session limit",
            state: .noWindow,
            displayedUtilization: 0,
            percentText: "0%",
            fillFraction: 0,
            fillColor: .blue,
            paceMarker: nil,
            resetLine: "Starts with your next message",
            paceText: nil,
            paceTextColor: .secondary,
            accessibilityText: "Session limit, 0%, starts with your next message"
        ))
    }

    @Test(arguments: ["2026-10-04T10:07:59.990Z", "2026-10-04T10:08:00Z"])
    func aResetTimeThatHasPassedMeansNoWindow(resetsAt: String) {
        let limit = session(utilization: 71, resetsAt: resetsAt)

        let display = limitDisplay(limit, now: now, timeZone: berlin, locale: enDE)

        #expect(display.state == .noWindow)
        #expect(display.percentText == "0%")
        #expect(display.paceMarker == nil)
        #expect(display.resetLine == "Starts with your next message")
    }
}

/// The reset line (§3 Reset line), with `now` on a full minute unless a
/// test says otherwise.
@Suite struct ResetLineTests {
    @Test(arguments: [
        ("2026-10-04T10:08:30Z", "Resets in 1 min"),
        ("2026-10-04T11:00:00Z", "Resets in 52 min"),
        ("2026-10-04T11:07:30Z", "Resets in 1 hr"),
        ("2026-10-04T12:00:00Z", "Resets in 1 hr 52 min"),
        ("2026-10-04T12:08:00Z", "Resets in 2 hr"),
        ("2026-10-05T10:07:00Z", "Resets in 23 hr 59 min"),
        ("2026-10-05T10:08:00Z", "Resets Mon 12:08"),
    ])
    func belowADayAwayItCountsDown(resetsAt: String, resetLine: String) {
        #expect(resetLineOf(weekly(utilization: 10, resetsAt: resetsAt), at: now) == resetLine)
    }

    @Test func theCountdownRoundsUp() {
        let now = date("2026-10-04T10:08:20Z")

        #expect(resetLineOf(session(utilization: 10, resetsAt: "2026-10-04T12:00:00Z"), at: now)
            == "Resets in 1 hr 52 min")
    }

    @Test func aResetTimeThatRoundsToBeforeNowShows1Min() {
        let now = date("2026-10-04T10:08:20Z")

        #expect(resetLineOf(session(utilization: 10, resetsAt: "2026-10-04T10:08:25Z"), at: now)
            == "Resets in 1 min")
    }

    @Test func theResetTimeRoundsToTheNearestMinuteFirst() {
        let limit = weekly(utilization: 10, resetsAt: "2026-10-07T00:59:59.880Z")

        #expect(resetLineOf(limit, at: now) == "Resets Wed 03:00")
    }

    @Test(arguments: [
        ("en_DE", "Resets Wed 03:00"),
        ("de_DE", "Resets Wed 03:00"),
        // The formatter puts a narrow no-break space before AM.
        ("en_US", "Resets Wed 3:00\u{202F}AM"),
        ("en_US@hours=h23", "Resets Wed 03:00"),
    ])
    func theWeekdayFormIsEnglishWithTheRegionAndHourCycleOfTheLocale(locale: String, resetLine: String) {
        let limit = weekly(utilization: 10, resetsAt: "2026-10-07T01:00:00Z")

        #expect(resetLineOf(limit, at: now, locale: Locale(identifier: locale)) == resetLine)
    }

    @Test func theWeekdayFormUsesTheTimeZone() {
        let limit = weekly(utilization: 10, resetsAt: "2026-10-07T01:00:00Z")

        let display = limitDisplay(limit, now: now, timeZone: TimeZone(identifier: "America/New_York")!, locale: enDE)

        #expect(display.resetLine == "Resets Tue 21:00")
    }

    private func resetLineOf(_ limit: Limit, at now: Date, locale: Locale = enDE) -> String {
        limitDisplay(limit, now: now, timeZone: berlin, locale: locale).resetLine
    }
}

/// Sunday, 4 Oct 2026, 12:08 in Berlin.
let now = date("2026-10-04T10:08:00Z")
let berlin = TimeZone(identifier: "Europe/Berlin")!
let enDE = Locale(identifier: "en_DE")

func date(_ iso8601: String) -> Date {
    try! Date(iso8601, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: iso8601.contains(".")))
}

func session(utilization: Double, resetsAt: String) -> Limit {
    Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
          window: ActiveWindow(utilization: utilization, resetsAt: date(resetsAt)))
}

func weekly(utilization: Double, resetsAt: String) -> Limit {
    Limit(id: "weekly", title: "Weekly limit", windowLength: 7 * 86400,
          window: ActiveWindow(utilization: utilization, resetsAt: date(resetsAt)))
}
