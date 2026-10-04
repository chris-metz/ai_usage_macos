import Foundation
import PacemarkKit
import Testing

/// When the app model queries and what it keeps of each result (§6.2,
/// §6.4), with a scripted provider, a fixed clock and a fake timer.
@Suite(.timeLimit(.minutes(1)))
struct AppModelQueryTests {
    /// Hours before any reset of `claudeLimits`.
    let launchedAt = Date(timeIntervalSince1970: 1_789_980_000)

    @Test func aSuccessKeepsTheLimitsAndWhenItFinished() async {
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), clock: { launchedAt },
                             sleep: { try await timer.sleep($0) })

        model.launch()
        _ = await timer.armed()

        #expect(model.state == ProviderState(lastAttemptAt: launchedAt, lastOutcome: .success,
                                             limits: claudeLimits, lastSuccessAt: launchedAt))
    }

    @Test func unavailableKeepsTheLimitsAndRetriesAfter1Then2Minutes() async {
        var time = launchedAt
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .unavailable, .unavailable),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        time += await timer.armed()

        timer.fire()
        let firstRetry = await timer.armed()
        time += firstRetry
        timer.fire()
        let secondRetry = await timer.armed()

        #expect([firstRetry, secondRetry] == [60, 2 * 60])
        #expect(model.state == ProviderState(lastAttemptAt: launchedAt + 5 * 60 + 60, lastOutcome: .unavailable,
                                             limits: claudeLimits, lastSuccessAt: launchedAt, failureStreak: 2))
    }

    @Test func aProblemClearsTheLimitsAndTheFailureStreak() async {
        var time = launchedAt
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .unavailable, .problem(notLoggedIn)),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        time += await timer.armed()
        timer.fire()
        time += await timer.armed()

        timer.fire()
        let next = await timer.armed()

        #expect(model.state == ProviderState(lastAttemptAt: launchedAt + 5 * 60 + 60, lastOutcome: .problem(notLoggedIn),
                                             limits: nil, lastSuccessAt: launchedAt, failureStreak: 0))
        #expect(next == 5 * 60)
    }

    @Test func aSuccessEndsTheFailureStreak() async {
        var time = launchedAt
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.unavailable, .limits(claudeLimits)),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        time += await timer.armed()

        timer.fire()
        let next = await timer.armed()

        #expect(model.state == ProviderState(lastAttemptAt: launchedAt + 60, lastOutcome: .success,
                                             limits: claudeLimits, lastSuccessAt: launchedAt + 60, failureStreak: 0))
        #expect(next == 5 * 60)
    }

    @Test func openingTheDropdownAfterAMinuteQueriesAndRecomputesTheNextQuery() async {
        var time = launchedAt
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .unavailable),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()

        time += 61
        model.dropdownOpened()
        let next = await timer.armed()

        #expect(model.state.lastAttemptAt == launchedAt + 61)
        #expect(model.now == launchedAt + 61)
        #expect(next == 60)
    }

    @Test func openingTheDropdownWithinAMinuteOnlyUpdatesNow() async {
        var time = launchedAt
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()

        time += 59
        model.dropdownOpened()

        #expect(!model.state.isQuerying)
        #expect(model.now == launchedAt + 59)
    }

    @Test func aTriggerDuringAQueryIsDroppedAndTheNextTimeCountsFromItsEnd() async {
        var time = launchedAt
        let timer = FakeTimer()
        let provider = FakeProvider(.limits(claudeLimits))
        let model = AppModel(provider: provider, clock: { time }, sleep: { try await timer.sleep($0) })

        model.launch()
        // The launch query runs until the test waits; opening the dropdown
        // before any attempt would query.
        time += 3
        model.dropdownOpened()
        let next = await timer.armed()

        #expect(provider.fetchCount == 1)
        #expect(model.state.lastAttemptAt == launchedAt + 3)
        #expect(next == 5 * 60)
    }
}

/// A persistent error as a provider might report it.
let notLoggedIn = Problem(heading: "Not logged in", message: "Run `claude` to log in.", link: nil)
