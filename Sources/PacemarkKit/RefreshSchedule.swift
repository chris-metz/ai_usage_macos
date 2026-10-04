import Foundation

/// What the app knows about one provider's queries (§6.2).
public nonisolated struct ProviderState: Equatable, Sendable {
    /// When the last query finished; nil before the first.
    public var lastAttemptAt: Date?
    /// The result of the last query; nil before the first.
    public var lastOutcome: QueryOutcome?
    /// The limits from the last success, in provider order; cleared by a
    /// problem.
    public var limits: [Limit]?
    /// When the last success finished.
    public var lastSuccessAt: Date?
    /// Consecutive `unavailable` outcomes.
    public var failureStreak: Int
    /// A query is running.
    public var isQuerying: Bool

    public init(
        lastAttemptAt: Date? = nil,
        lastOutcome: QueryOutcome? = nil,
        limits: [Limit]? = nil,
        lastSuccessAt: Date? = nil,
        failureStreak: Int = 0,
        isQuerying: Bool = false
    ) {
        self.lastAttemptAt = lastAttemptAt
        self.lastOutcome = lastOutcome
        self.limits = limits
        self.lastSuccessAt = lastSuccessAt
        self.failureStreak = failureStreak
        self.isQuerying = isQuerying
    }

    /// Records how the running query ended (§6.4): a success stores the
    /// limits, a temporary error keeps them and raises the failure streak,
    /// a problem clears them.
    public mutating func record(_ result: FetchResult, finishedAt: Date) {
        isQuerying = false
        lastAttemptAt = finishedAt
        switch result {
        case .limits(let limits):
            self.limits = limits
            lastSuccessAt = finishedAt
            lastOutcome = .success
            failureStreak = 0
        case .unavailable:
            lastOutcome = .unavailable
            failureStreak += 1
        case .problem(let problem):
            limits = nil
            lastOutcome = .problem(problem)
            failureStreak = 0
        }
    }
}

/// How a query ended.
public nonisolated enum QueryOutcome: Equatable, Sendable {
    case success
    case unavailable
    case problem(Problem)
}

/// When the next scheduled query runs (§6.2): the earliest of the launch,
/// the retry or refresh interval after the last attempt, and 65 s after
/// every reset time. Never before `now`: a time that has passed means
/// "query now".
public nonisolated func nextQueryAt(_ state: ProviderState, interval: TimeInterval, now: Date) -> Date {
    guard let lastAttemptAt = state.lastAttemptAt else { return now }
    let wait: TimeInterval = switch state.failureStreak {
    case 1: 60
    case 2: 2 * 60
    default: interval
    }
    // Every limit, also one the dropdown hides. The 65 s get past the
    // provider's own 60 s snapshot (§6.2).
    let afterResets = (state.limits ?? [])
        .compactMap { $0.window?.resetsAt.addingTimeInterval(65) }
        .filter { $0 > lastAttemptAt }
    let next = ([lastAttemptAt.addingTimeInterval(wait)] + afterResets).min()!
    return max(next, now)
}

/// When the minute tick updates `now` next: the next full minute (§6.4).
public nonisolated func nextFullMinute(after date: Date) -> Date {
    let minutes = (date.timeIntervalSinceReferenceDate / 60).rounded(.down) + 1
    return Date(timeIntervalSinceReferenceDate: minutes * 60)
}

/// Opening the dropdown queries if the last attempt is more than 60 s old,
/// in every state, so a fixed error disappears as soon as you look (§6.2).
public nonisolated func shouldQueryOnOpen(_ state: ProviderState, now: Date) -> Bool {
    guard let lastAttemptAt = state.lastAttemptAt else { return true }
    return now.timeIntervalSince(lastAttemptAt) > 60
}
