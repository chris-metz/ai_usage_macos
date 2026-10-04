import Foundation
import Observation

/// The app's state: the provider, its last limits and the current time.
/// The menu bar item and the dropdown render from it.
@Observable public final class AppModel {
    public let provider: any Provider
    /// The limits of the last successful query, in provider order.
    public private(set) var limits: [Limit] = []
    /// The time everything renders at. Set at launch and after every query.
    public private(set) var now: Date

    @ObservationIgnored private let clock: () -> Date

    public init(provider: any Provider, clock: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.clock = clock
        now = clock()
    }

    /// What the menu bar item shows: the first limit's percentage, or the
    /// glyph alone before the first result.
    public var menuBarDisplay: MenuBarDisplay {
        guard let limit = limits.first else {
            return MenuBarDisplay(percentText: nil, accessibilityText: "Pacemark")
        }
        let percent = percentText(limit)
        return MenuBarDisplay(percentText: percent, accessibilityText: "\(limit.title) \(percent)")
    }

    /// Runs one query and records its result.
    public func query() async {
        let result = await provider.fetch()
        if case .limits(let limits) = result {
            self.limits = limits
        }
        now = clock()
    }

    /// Interim until the refresh schedule (§6.2): a query at once and then
    /// every 5 min, until the task is cancelled.
    public func queryEvery5Minutes() async {
        while !Task.isCancelled {
            await query()
            try? await Task.sleep(for: .seconds(5 * 60))
        }
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
