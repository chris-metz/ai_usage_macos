import Foundation

/// The user's settings (§6.5), each with its default. Limits are named by
/// their qualified id, `{provider.id}/{limit.id}`, e.g. `claude/session`.
public nonisolated struct Settings: Equatable, Sendable {
    /// How often the app queries: 5, 10 or 15 minutes.
    public var refreshIntervalMinutes: Int
    /// The menu bar item shows the percentage next to the glyph.
    public var showPercentage: Bool
    /// Qualified ids of the limits the dropdown hides. Only these are
    /// remembered, so a new model limit shows.
    public var hiddenLimits: [String]
    /// Qualified id of the menu bar limit; nil means the first limit.
    public var menuBarLimitID: String?
    /// The menu bar limit's title when it was picked, for `(not available)`.
    public var menuBarLimitTitle: String?

    /// The refresh interval choices, in minutes.
    public static let refreshIntervalChoices = [5, 10, 15]

    public init(
        refreshIntervalMinutes: Int = 5,
        showPercentage: Bool = true,
        hiddenLimits: [String] = [],
        menuBarLimitID: String? = nil,
        menuBarLimitTitle: String? = nil
    ) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.showPercentage = showPercentage
        self.hiddenLimits = hiddenLimits
        self.menuBarLimitID = menuBarLimitID
        self.menuBarLimitTitle = menuBarLimitTitle
    }

    /// The refresh interval in seconds.
    public var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    /// Whether the dropdown shows `limit` of the provider `providerID`:
    /// every limit but the hidden ones.
    public func isLimitShownInDropdown(_ limit: Limit, providerID: String) -> Bool {
        !hiddenLimits.contains(limit.qualifiedID(providerID: providerID))
    }
}
