import Foundation
import Observation
import os

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
    /// The network path's last status; unknown counts as not satisfied.
    @ObservationIgnored private var isNetworkSatisfied = false
    /// After a wake without network, the query runs at this time at the
    /// latest; nil when no wake waits.
    @ObservationIgnored private var wakeDeadline: Date?

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

    // MARK: Events

    /// The app has launched: the first query runs at once.
    public func launch() {
        schedule()
    }

    /// The dropdown opened: it renders at the current time, and queries if
    /// the last attempt is more than a minute old.
    public func dropdownOpened() {
        now = clock()
        if shouldQueryOnOpen(state, now: now) {
            query(.dropdown)
        }
    }

    /// The Mac woke from sleep: query as soon as the network is up, at the
    /// latest 30 s from now.
    public func wake() {
        if isNetworkSatisfied {
            query(.wake)
        } else {
            appLog.info("Woke without network: waiting for it for up to 30 s")
            wakeDeadline = clock().addingTimeInterval(30)
            schedule()
        }
    }

    /// The network path changed. When it comes back after a wake or a
    /// temporary error, the query runs at once.
    public func networkChanged(isSatisfied: Bool) {
        guard isSatisfied != isNetworkSatisfied else { return }
        isNetworkSatisfied = isSatisfied
        appLog.info("Network path \(isSatisfied ? "satisfied" : "not satisfied", privacy: .public)")
        if isSatisfied, wakeDeadline != nil || state.lastOutcome == .unavailable {
            query(.network)
        }
    }

    /// A full minute has passed: everything time-dependent re-renders.
    public func minuteTick() {
        now = clock()
    }

    // MARK: Queries

    /// Queries now if the schedule says so, and otherwise arms the timer for
    /// the next scheduled query.
    private func schedule() {
        timer?.cancel()
        timer = nil
        guard !state.isQuerying else { return }
        let now = clock()
        var next = nextQueryAt(state, interval: refreshInterval, now: now)
        if let wakeDeadline {
            next = min(next, wakeDeadline)
        }
        guard next > now else {
            query(.schedule)
            return
        }
        appLog.info("Next query at \(next.formatted(.iso8601), privacy: .public)")
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
    private func query(_ trigger: QueryTrigger) {
        guard !state.isQuerying else {
            appLog.info("Dropped the \(trigger.rawValue, privacy: .public) trigger: a query is running")
            return
        }
        appLog.info("Query started by the \(trigger.rawValue, privacy: .public) trigger")
        state.isQuerying = true
        wakeDeadline = nil
        timer?.cancel()
        timer = nil
        let startedAt = clock()
        Task {
            let result = await provider.fetch()
            finish(result, startedAt: startedAt)
        }
    }

    /// Records the result (§6.4) and recomputes the next time.
    private func finish(_ result: FetchResult, startedAt: Date) {
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
        let seconds = finishedAt.timeIntervalSince(startedAt)
        appLog.info("Query finished after \(seconds, format: .fixed(precision: 1), privacy: .public) s: \(describe(result), privacy: .public)")
        schedule()
    }
}

/// What started a query, for the log.
private nonisolated enum QueryTrigger: String {
    /// Launch, a scheduled time, or a wake's 30 s deadline.
    case schedule
    case dropdown
    case wake
    case network
}

private nonisolated func describe(_ result: FetchResult) -> String {
    switch result {
    case .limits(let limits): "\(limits.count) limits"
    case .unavailable: "unavailable"
    case .problem(let problem): "problem \"\(problem.heading)\""
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
