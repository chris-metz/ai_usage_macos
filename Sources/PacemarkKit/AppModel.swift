import Foundation
import Observation

/// The app's state: the provider, its last limits and the current time.
/// The menu bar item and the dropdown render from it.
@Observable public final class AppModel {
    public let provider: any Provider
    /// The limits of the last successful query, in provider order.
    public private(set) var limits: [Limit] = []
    /// The time everything renders at. Set at launch, when the dropdown
    /// opens and after every query.
    public private(set) var now: Date

    @ObservationIgnored private let clock: () -> Date

    public init(provider: any Provider, clock: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.clock = clock
        now = clock()
    }

    /// What the menu bar item shows: the displayed utilization of the menu
    /// bar limit (for now the first limit), or the glyph alone before the
    /// first result.
    public var menuBarDisplay: MenuBarDisplay {
        guard let limit = limits.first else {
            return MenuBarDisplay(percentText: nil, accessibilityText: "Pacemark")
        }
        let percent = limitDisplay(limit, now: now).percentText
        return MenuBarDisplay(percentText: percent, accessibilityText: "\(limit.title) \(percent)")
    }

    /// The dropdown opened: render it at the current time.
    public func dropdownOpened() {
        now = clock()
    }

    /// Runs one query. A success replaces the limits; anything else keeps
    /// them until the refresh schedule's bookkeeping (§6.4) arrives.
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
