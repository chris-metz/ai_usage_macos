import Foundation
import PacemarkKit
import Testing

/// When the next query runs (§6.2), with fixed dates.
@Suite struct RefreshScheduleTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func launchQueriesNow() {
        #expect(nextQueryAt(ProviderState(), interval: 5 * 60, now: now) == now)
    }

    @Test(arguments: [5, 10, 15])
    func afterASuccessTheNextQueryIsOneIntervalAfterTheLastAttempt(minutes: Int) {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .success, limits: [], lastSuccessAt: now)

        #expect(nextQueryAt(state, interval: TimeInterval(minutes * 60), now: now)
            == now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    @Test(arguments: [
        (failures: 1, retryAfterMinutes: 1),
        (failures: 2, retryAfterMinutes: 2),
        (failures: 3, retryAfterMinutes: 10),
    ])
    func failuresRetryAfter1Then2MinutesThenAtTheInterval(failures: Int, retryAfterMinutes: Int) {
        let state = ProviderState(lastAttemptAt: now, lastOutcome: .unavailable, failureStreak: failures)

        #expect(nextQueryAt(state, interval: 10 * 60, now: now)
            == now.addingTimeInterval(TimeInterval(retryAfterMinutes * 60)))
    }

    /// Every limit counts, also one the dropdown hides: hiding is a display
    /// setting and never filters the state's limits.
    @Test func aResetBeforeTheIntervalQueries65SecondsAfterIt() {
        let resetsAt = now.addingTimeInterval(2 * 60)
        let state = ProviderState(
            lastAttemptAt: now, lastOutcome: .success,
            limits: [limit("session", resetsAt: now.addingTimeInterval(3 * 3600)),
                     limit("weekly", resetsAt: now.addingTimeInterval(3 * 86400)),
                     limit("model:Fable", resetsAt: resetsAt)],
            lastSuccessAt: now
        )

        #expect(nextQueryAt(state, interval: 5 * 60, now: now) == resetsAt.addingTimeInterval(65))
    }

    @Test func aResetWhose65SecondsEndedBeforeTheLastAttemptIsIgnored() {
        let state = ProviderState(
            lastAttemptAt: now, lastOutcome: .success,
            limits: [limit("session", resetsAt: now.addingTimeInterval(-66))],
            lastSuccessAt: now
        )

        #expect(nextQueryAt(state, interval: 5 * 60, now: now) == now.addingTimeInterval(5 * 60))
    }

    @Test func aLimitWithNoWindowDoesNotScheduleAnything() {
        let state = ProviderState(
            lastAttemptAt: now, lastOutcome: .success,
            limits: [Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)],
            lastSuccessAt: now
        )

        #expect(nextQueryAt(state, interval: 5 * 60, now: now) == now.addingTimeInterval(5 * 60))
    }

    /// The interval counts from the last attempt: 7 min ago at 10 min is
    /// still 3 min away, at 5 min it is overdue.
    @Test func aShorterIntervalWhoseTimeHasPassedQueriesNow() {
        let state = ProviderState(
            lastAttemptAt: now.addingTimeInterval(-7 * 60), lastOutcome: .success,
            limits: [], lastSuccessAt: now.addingTimeInterval(-7 * 60)
        )

        #expect(nextQueryAt(state, interval: 10 * 60, now: now) == now.addingTimeInterval(3 * 60))
        #expect(nextQueryAt(state, interval: 5 * 60, now: now) == now)
    }

    @Test(arguments: [
        (secondsAgo: 59, queries: false),
        (secondsAgo: 61, queries: true),
    ])
    func openingTheDropdownQueriesWhenTheLastAttemptIsMoreThan60SecondsOld(secondsAgo: Int, queries: Bool) {
        let state = ProviderState(lastAttemptAt: now.addingTimeInterval(-TimeInterval(secondsAgo)), lastOutcome: .unavailable)

        #expect(shouldQueryOnOpen(state, now: now) == queries)
    }

    @Test func openingTheDropdownBeforeAnyAttemptQueries() {
        #expect(shouldQueryOnOpen(ProviderState(), now: now))
    }

    @Test(arguments: [
        (time: "10:00:30", tick: "10:01:00"),
        (time: "10:01:00", tick: "10:02:00"),
        (time: "23:59:59", tick: "00:00:00"),
    ])
    func theMinuteTickComesOnTheNextFullMinute(time: String, tick: String) throws {
        let berlin = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "Europe/Berlin")!)

        let next = nextFullMinute(after: try berlin.parse("2026-10-04T\(time)+02:00"))

        #expect(berlin.format(next).contains("T\(tick)"))
    }

    private func limit(_ id: String, resetsAt: Date) -> Limit {
        Limit(id: id, title: id, windowLength: 7 * 86400, window: ActiveWindow(utilization: 50, resetsAt: resetsAt))
    }
}
