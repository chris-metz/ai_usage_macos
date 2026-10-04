import Foundation
import Observation

/// The app's state: the provider, its query state and the current time.
/// The menu bar item and the dropdown render from it.
///
/// Events come in as methods; the model decides when to query (§6.2) and
/// keeps one timer task for the next scheduled query.
@Observable public final class AppModel {
    public let provider: any Provider
    /// How long after the last attempt the next query runs.
    public let refreshInterval: TimeInterval
    /// What the model knows about the provider's queries.
    public private(set) var state = ProviderState()
    /// The time everything renders at.
    public private(set) var now: Date

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// - Parameters:
    ///   - clock: The current time.
    ///   - sleep: Waits the given number of seconds; throws when cancelled.
    public init(
        provider: any Provider,
        refreshInterval: TimeInterval = 5 * 60,
        clock: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.provider = provider
        self.refreshInterval = refreshInterval
        self.clock = clock
        self.sleep = sleep
        now = clock()
    }

    /// The limits of the last successful query, in provider order.
    public var limits: [Limit] { state.limits ?? [] }

    /// What the menu bar item shows: the first limit's percentage, or the
    /// glyph alone before the first result.
    public var menuBarDisplay: MenuBarDisplay {
        guard let limit = limits.first else {
            return MenuBarDisplay(percentText: nil, accessibilityText: "Pacemark")
        }
        let percent = percentText(limit)
        return MenuBarDisplay(percentText: percent, accessibilityText: "\(limit.title) \(percent)")
    }

    /// The app has launched: the first query runs at once.
    public func launch() {
        schedule()
    }

    /// The dropdown opened: it renders at the current time, and queries if
    /// the last attempt is more than a minute old.
    public func dropdownOpened() {
        now = clock()
        if shouldQueryOnOpen(state, now: now) {
            query()
        }
    }

    /// Queries now if the schedule says so, and otherwise arms the timer for
    /// the next scheduled query.
    private func schedule() {
        timer?.cancel()
        timer = nil
        guard !state.isQuerying else { return }
        let now = clock()
        let next = nextQueryAt(state, interval: refreshInterval, now: now)
        guard next > now else {
            query()
            return
        }
        timer = Task { [weak self, sleep] in
            do {
                try await sleep(next.timeIntervalSince(now))
            } catch {
                return
            }
            self?.schedule()
        }
    }

    /// Starts a query unless one runs: a trigger during a query is dropped,
    /// and the query's end recomputes the next time.
    private func query() {
        guard !state.isQuerying else { return }
        state.isQuerying = true
        timer?.cancel()
        timer = nil
        Task {
            let result = await provider.fetch()
            finish(result)
        }
    }

    private func finish(_ result: FetchResult) {
        let finishedAt = clock()
        state.isQuerying = false
        state.lastAttemptAt = finishedAt
        switch result {
        case .limits(let limits):
            state.limits = limits
            state.lastSuccessAt = finishedAt
            state.lastOutcome = .success
            state.failureStreak = 0
        case .unavailable:
            state.lastOutcome = .unavailable
            state.failureStreak += 1
        case .problem(let problem):
            state.limits = nil
            state.lastOutcome = .problem(problem)
            state.failureStreak = 0
        }
        now = finishedAt
        schedule()
    }
}

/// The limit's displayed utilization, e.g. `14%`: rounded to a whole
/// number, at most 100, and 0 with no window.
///
/// Interim: the full rule, including a reset time that has passed, comes
/// with the limit display (§6.1).
nonisolated func percentText(_ limit: Limit) -> String {
    let utilization = min(max(limit.window?.utilization ?? 0, 0), 100)
    return "\(Int(utilization.rounded()))%"
}
