import Foundation
import Observation
import os

/// The app's state: the provider, its query state, the settings and the
/// current time. The menu bar item, the dropdown and the settings window
/// render from it.
///
/// Events come in as methods; the model decides when to query (§6.2) and
/// keeps one timer task for the next scheduled query.
@Observable public final class AppModel {
    public let provider: any Provider
    /// The user's settings, written through to the store on every change.
    /// A new refresh interval counts from the last attempt, so if that time
    /// has passed, the query runs now (§6.2).
    public var settings: Settings {
        didSet {
            settingsStore?.save(settings)
            if settings.refreshIntervalMinutes != oldValue.refreshIntervalMinutes {
                appLog.info("Refresh interval changed to \(self.settings.refreshIntervalMinutes, privacy: .public) min")
                schedule()
            }
        }
    }
    /// What the model knows about the provider's queries.
    public private(set) var state = ProviderState()
    /// The time everything renders at. Set at launch, on every full minute,
    /// when the dropdown opens and after every query.
    public private(set) var now: Date

    @ObservationIgnored private let settingsStore: SettingsStore?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The network path's last status; unknown counts as not satisfied.
    @ObservationIgnored private var isNetworkSatisfied = false
    /// After a wake without network, the query runs at this time at the
    /// latest; nil when no wake waits.
    @ObservationIgnored private var wakeDeadline: Date?

    /// - Parameters:
    ///   - settingsStore: Where the settings come from and go to; without
    ///     one, the model starts with the defaults and keeps changes to
    ///     itself.
    ///   - clock: The current time.
    ///   - sleep: Waits the given number of seconds; throws when cancelled.
    public init(
        provider: any Provider,
        settingsStore: SettingsStore? = nil,
        clock: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.provider = provider
        self.settingsStore = settingsStore
        settings = settingsStore?.load() ?? Settings()
        self.clock = clock
        self.sleep = sleep
        now = clock()
    }

    /// What the menu bar item and the dropdown show at `now` (§6.3).
    public var display: Display {
        PacemarkKit.display(state, providerID: provider.id, settings: settings, now: now)
    }

    // MARK: Settings window

    /// How the settings name `limit`, one of this provider's.
    public func qualifiedID(of limit: Limit) -> String {
        limit.qualifiedID(providerID: provider.id)
    }

    /// Makes `limit` the menu bar limit: stores its qualified id, and its
    /// title for when it goes missing (`(not available)`).
    public func pickMenuBarLimit(_ limit: Limit) {
        settings.menuBarLimitID = qualifiedID(of: limit)
        settings.menuBarLimitTitle = limit.title
    }

    /// Whether the dropdown shows `limit`.
    public func isLimitShownInDropdown(_ limit: Limit) -> Bool {
        !settings.hiddenLimits.contains(qualifiedID(of: limit))
    }

    /// Shows or hides `limit` in the dropdown. Other stored hidden limits
    /// stay, whether or not the provider currently delivers them.
    public func setLimit(_ limit: Limit, shownInDropdown isShown: Bool) {
        let id = qualifiedID(of: limit)
        if isShown {
            settings.hiddenLimits.removeAll { $0 == id }
        } else if !settings.hiddenLimits.contains(id) {
            settings.hiddenLimits.append(id)
        }
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
        var next = nextQueryAt(state, interval: settings.refreshInterval, now: now)
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
