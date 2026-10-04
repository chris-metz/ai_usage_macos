import Foundation

/// Everything a dropdown row shows for one limit (§3, §6.1).
public nonisolated struct LimitDisplay: Equatable, Sendable {
    public var title: String
    public var state: LimitState
    /// `U`: the utilization rounded to a whole number and clamped to 0–100;
    /// 0 with no window.
    public var displayedUtilization: Int
    /// `{U}%`, e.g. `71%`.
    public var percentText: String
    /// How much of the bar the fill covers, 0–1.
    public var fillFraction: Double
    public var fillColor: LimitColor
    /// Where the pace marker sits, as a fraction of the bar width; nil with
    /// no window.
    public var paceMarker: Double?
    /// Line 2, left, e.g. `Resets in 1 hr 52 min`.
    public var resetLine: String
    /// Line 2, right, e.g. `8% over pace`; nil with no window.
    public var paceText: String?
    public var paceTextColor: LimitColor
    /// The row as one accessibility element, e.g.
    /// `Session limit, 71%, 8% over pace, resets in 1 hr 52 min`.
    public var accessibilityText: String

    public init(
        title: String,
        state: LimitState,
        displayedUtilization: Int,
        percentText: String,
        fillFraction: Double,
        fillColor: LimitColor,
        paceMarker: Double?,
        resetLine: String,
        paceText: String?,
        paceTextColor: LimitColor,
        accessibilityText: String
    ) {
        self.title = title
        self.state = state
        self.displayedUtilization = displayedUtilization
        self.percentText = percentText
        self.fillFraction = fillFraction
        self.fillColor = fillColor
        self.paceMarker = paceMarker
        self.resetLine = resetLine
        self.paceText = paceText
        self.paceTextColor = paceTextColor
        self.accessibilityText = accessibilityText
    }
}

/// The limit states of §3, in the order they are checked.
public nonisolated enum LimitState: Equatable, Sendable {
    case noWindow
    case exhausted
    case high
    case overPace
    case onPace
    case underPace
}

/// The colours a row uses; the view maps them to the macOS system colours.
public nonisolated enum LimitColor: Equatable, Sendable {
    case blue
    case orange
    case red
    case green
    case secondary
}

/// How much of `limit` is used at `now` and whether that is on pace (§6.1).
///
/// The reset line uses `timeZone` and `locale` with the language replaced by
/// English, so only the region and the hour cycle of `locale` count.
public nonisolated func limitDisplay(
    _ limit: Limit,
    now: Date,
    timeZone: TimeZone = .autoupdatingCurrent,
    locale: Locale = .autoupdatingCurrent
) -> LimitDisplay {
    guard let window = limit.window, window.resetsAt > now else {
        let resetLine = "Starts with your next message"
        return LimitDisplay(
            title: limit.title,
            state: .noWindow,
            displayedUtilization: 0,
            percentText: "0%",
            fillFraction: 0,
            fillColor: .blue,
            paceMarker: nil,
            resetLine: resetLine,
            paceText: nil,
            paceTextColor: .secondary,
            accessibilityText: "\(limit.title), 0%, \(resetLine.lowercasedFirstLetter)"
        )
    }
    let utilization = min(max(window.utilization, 0), 100)
    let displayed = Int(utilization.rounded())
    let windowStart = window.resetsAt.addingTimeInterval(-limit.windowLength)
    let pace = min(max(now.timeIntervalSince(windowStart) / limit.windowLength * 100, 0), 100)
    let deviation = Int((utilization - pace).rounded())
    let percentText = "\(displayed)%"

    var state: LimitState
    var paceText: String
    var paceTextColor: LimitColor
    if deviation >= 1 {
        (state, paceText, paceTextColor) = (.overPace, "\(deviation)% over pace", .orange)
    } else if deviation == 0 {
        (state, paceText, paceTextColor) = (.onPace, "On pace", .secondary)
    } else {
        (state, paceText, paceTextColor) = (.underPace, "\(-deviation)% under pace", .green)
    }
    if displayed == 100 {
        (state, paceText, paceTextColor) = (.exhausted, "Limit reached", .red)
    } else if displayed >= 90 {
        state = .high
    }
    let fillColor: LimitColor = switch state {
    case .exhausted, .high: .red
    case .overPace: .orange
    case .noWindow, .onPace, .underPace: .blue
    }

    let resetLine = resetLine(window.resetsAt, now: now)
    return LimitDisplay(
        title: limit.title,
        state: state,
        displayedUtilization: displayed,
        percentText: percentText,
        fillFraction: Double(displayed) / 100,
        fillColor: fillColor,
        paceMarker: pace / 100,
        resetLine: resetLine,
        paceText: paceText,
        paceTextColor: paceTextColor,
        accessibilityText: "\(limit.title), \(percentText), \(paceText), \(resetLine.lowercasedFirstLetter)"
    )
}

/// `Resets in 1 hr 52 min` (§3 Reset line).
private nonisolated func resetLine(_ resetsAt: Date, now: Date) -> String {
    let minutes = Int((resetsAt.timeIntervalSince(now) / 60).rounded(.up))
    return "Resets in \(minutes / 60) hr \(minutes % 60) min"
}

private nonisolated extension String {
    var lowercasedFirstLetter: String {
        prefix(1).lowercased() + dropFirst()
    }
}
