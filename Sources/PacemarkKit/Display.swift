import Foundation

/// Everything the menu bar item and the dropdown show (§6.3).
public nonisolated struct Display: Equatable, Sendable {
    /// What the dropdown shows above its footer.
    public var dropdown: DropdownContent
    /// `Couldn't update · Last update 23 min ago` while the values are
    /// stale; nil otherwise.
    public var staleLine: String?
    public var menuBar: MenuBarDisplay

    public init(dropdown: DropdownContent, staleLine: String?, menuBar: MenuBarDisplay) {
        self.dropdown = dropdown
        self.staleLine = staleLine
        self.menuBar = menuBar
    }
}

/// What the dropdown shows above its footer (§3 Other contents).
public nonisolated enum DropdownContent: Equatable, Sendable {
    /// No query has finished since launch.
    case loading
    /// A persistent error: its heading, message and link.
    case problem(Problem)
    /// One row per limit, in provider order.
    case limits([Limit])
    /// The last query failed temporarily and nothing has loaded yet.
    case noValues
}

/// What the menu bar item and the dropdown show for `state` at `now`
/// (§6.3).
public nonisolated func display(_ state: ProviderState, settings: Settings, now: Date) -> Display {
    let staleAge = staleAge(state, interval: TimeInterval(settings.refreshIntervalMinutes * 60), now: now)
    let dropdown: DropdownContent = switch (state.lastOutcome, state.limits) {
    case (nil, _): .loading
    case (.problem(let problem)?, _): .problem(problem)
    case (_, let limits?): .limits(limits)
    default: .noValues
    }
    return Display(
        dropdown: dropdown,
        staleLine: staleAge.map(staleLine),
        menuBar: menuBarDisplay(state, isStale: staleAge != nil, now: now)
    )
}

/// The menu bar item (§2 States), with the percentage on. The menu bar limit
/// is the first limit.
private nonisolated func menuBarDisplay(_ state: ProviderState, isStale: Bool, now: Date) -> MenuBarDisplay {
    if case .problem(let problem) = state.lastOutcome {
        return MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: \(problem.heading)")
    }
    guard let limit = state.limits?.first else {
        return MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")
    }
    let shown = limitDisplay(limit, now: now)
    return MenuBarDisplay(
        content: .percentage(shown.percentText, isRed: shown.displayedUtilization >= 90, isDimmed: isStale),
        accessibilityText: "\(limit.title) \(shown.percentText)" + (isStale ? ", not up to date" : "")
    )
}

/// How long ago the last success finished, if the values are stale: the
/// last query failed temporarily, there are values, and they are more than
/// two refresh intervals old. A query still running doesn't count as failed.
private nonisolated func staleAge(_ state: ProviderState, interval: TimeInterval, now: Date) -> TimeInterval? {
    guard state.lastOutcome == .unavailable, state.limits != nil, let lastSuccessAt = state.lastSuccessAt else {
        return nil
    }
    let age = now.timeIntervalSince(lastSuccessAt)
    return age > 2 * interval ? age : nil
}

/// `Couldn't update · Last update 23 min ago`, with the age in `min` below an
/// hour, in `hr` below a day and in days from then on, each rounded down.
private nonisolated func staleLine(age: TimeInterval) -> String {
    let minutes = Int(age / 60)
    let text = switch minutes {
    case ..<60: "\(minutes) min"
    case ..<(24 * 60): "\(minutes / 60) hr"
    case ..<(2 * 24 * 60): "1 day"
    default: "\(minutes / (24 * 60)) days"
    }
    return "Couldn't update · Last update \(text) ago"
}
