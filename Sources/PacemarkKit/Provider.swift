import Foundation

/// A source of limits, e.g. Claude. The app triggers every query; the
/// provider is passive and keeps no limit values across calls.
public nonisolated protocol Provider: Sendable {
    /// Stable id, never shown, e.g. "claude". Prefixes the stored limit ids.
    var id: String { get }
    /// Display name, e.g. "Claude". Unused in v1 (no tab bar).
    var name: String { get }
    /// Runs one query. Never called concurrently for the same provider;
    /// runs off the main actor.
    func fetch() async -> FetchResult
}

/// The answer to one query: exactly one of three results.
public nonisolated enum FetchResult: Equatable, Sendable {
    /// Success, in display order; the first is the default menu bar limit.
    case limits([Limit])
    /// Temporary error: old values stay, the retry schedule applies.
    case unavailable
    /// Persistent error: old values go, the message replaces the bars.
    case problem(Problem)
}

public nonisolated struct Limit: Equatable, Sendable, Identifiable {
    /// Unique within the provider, stable, never shown.
    public let id: String
    /// Label above the bar.
    public let title: String
    public let windowLength: TimeInterval
    /// nil = no window.
    public let window: ActiveWindow?

    public init(id: String, title: String, windowLength: TimeInterval, window: ActiveWindow?) {
        self.id = id
        self.title = title
        self.windowLength = windowLength
        self.window = window
    }
}

/// A running window: utilization and reset time come together or not at all.
public nonisolated struct ActiveWindow: Equatable, Sendable {
    /// Percent as delivered; may exceed 100.
    public let utilization: Double
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// A persistent error, with finished text supplied by the provider.
public nonisolated struct Problem: Equatable, Sendable {
    public let heading: String
    /// Markdown, so commands render as inline code.
    public let message: String
    public let link: ProblemLink?

    public init(heading: String, message: String, link: ProblemLink?) {
        self.heading = heading
        self.message = message
        self.link = link
    }
}

public nonisolated struct ProblemLink: Equatable, Sendable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}
