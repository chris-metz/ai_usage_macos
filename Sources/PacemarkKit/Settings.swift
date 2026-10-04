import Foundation

/// The user's choices (§6.5), each with its default. The store reads and
/// writes them; this type knows nothing about storage.
public nonisolated struct Settings: Equatable, Sendable {
    /// How often Pacemark queries: 5, 10 or 15 minutes.
    public var refreshIntervalMinutes: Int
    /// The menu bar item shows the menu bar limit's percentage.
    public var showPercentage: Bool
    /// Qualified ids of the limits hidden in the dropdown, e.g.
    /// `claude/model:Fable`.
    public var hiddenLimits: [String]
    /// Qualified id of the menu bar limit; nil means the first limit.
    public var menuBarLimitID: String?
    /// The menu bar limit's title when it was picked, for `(not available)`.
    public var menuBarLimitTitle: String?

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
}
