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
    if case .problem(let problem) = state.lastOutcome {
        return Display(
            dropdown: .problem(problem),
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .warning, accessibilityText: "Pacemark: \(problem.heading)")
        )
    }
    guard let limits = state.limits, let menuBarLimit = limits.first else {
        return Display(
            dropdown: state.lastOutcome == nil ? .loading : .noValues,
            staleLine: nil,
            menuBar: MenuBarDisplay(content: .glyph, accessibilityText: "Pacemark")
        )
    }
    let shown = limitDisplay(menuBarLimit, now: now)
    return Display(
        dropdown: .limits(limits),
        staleLine: nil,
        menuBar: MenuBarDisplay(
            content: .percentage(shown.percentText, isRed: shown.displayedUtilization >= 90),
            accessibilityText: "\(menuBarLimit.title) \(shown.percentText)"
        )
    )
}
