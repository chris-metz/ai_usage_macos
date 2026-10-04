import Foundation
import PacemarkKit
import Testing

@testable import PacemarkClaude

private let fiveHours: TimeInterval = 5 * 60 * 60
private let sevenDays: TimeInterval = 7 * 24 * 60 * 60

@Suite struct UsageParserTests {
    @Test func usageFixtureGivesSessionWeeklyAndFableLimitsInOrder() throws {
        let limits = try parsedLimits("usage.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits.map(\.title) == ["Session limit", "Weekly limit", "Fable limit"])
        #expect(limits.map(\.windowLength) == [fiveHours, sevenDays, sevenDays])
        #expect(limits.map(\.window?.utilization) == [14, 36, 0])
        expectDate(limits[0].window?.resetsAt, near: 1_791_025_799.823825)  // 2026-10-03T11:09:59.823825Z
        expectDate(limits[1].window?.resetsAt, near: 1_791_334_799.823845)  // 2026-10-07T00:59:59.823845Z
        expectDate(limits[2].window?.resetsAt, near: 1_791_334_800)  // 2026-10-07T01:00:00Z
    }

    @Test func sessionRowWithoutResetTimeIsNoWindow() throws {
        let limits = try parsedLimits("usage-no-session-window.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits[0] == Limit(id: "session", title: "Session limit", windowLength: fiveHours, window: nil))
        #expect(limits[1].window?.utilization == 41)
    }

    @Test func missingSessionRowStillGivesASessionLimitFirst() throws {
        let limits = try parsedLimits("variant-no-session.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits[0] == Limit(id: "session", title: "Session limit", windowLength: fiveHours, window: nil))
    }

    @Test func orderIsSessionWeeklyThenModelsInServerOrder() throws {
        let limits = try parsedLimits("variant-two-models.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Opus", "model:Fable"])
        #expect(limits.map(\.title) == ["Session limit", "Weekly limit", "Opus limit", "Fable limit"])
        #expect(limits.map(\.windowLength) == [fiveHours, sevenDays, sevenDays, sevenDays])
        #expect(limits.map(\.window?.utilization) == [14, 36, 12, 0])
    }

    @Test(arguments: ["variant-unknown-kind.stream.jsonl", "variant-surface-scope.stream.jsonl"])
    func rowsOfOtherKindsOrScopesAreIgnored(fixture: String) throws {
        let limits = try parsedLimits(fixture)

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
    }

    @Test func nullPercentIsNoWindowEvenWithAResetTime() throws {
        let limits = try parsedLimits("variant-percent-null.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits[1] == Limit(id: "weekly", title: "Weekly limit", windowLength: sevenDays, window: nil))
        #expect(limits[0].window?.utilization == 14)
    }

    @Test func resetTimeWithoutFractionalSecondsParses() throws {
        let limits = try parsedLimits("variant-no-fractional-seconds.stream.jsonl")

        expectDate(limits[0].window?.resetsAt, near: 1_791_025_800)  // 2026-10-03T11:10:00Z
    }

    @Test func utilizationAbove100IsKeptAsDelivered() throws {
        let limits = try parsedLimits("variant-percent-over-100.stream.jsonl")

        #expect(limits[0].window?.utilization == 140)
    }

    @Test func repeatedModelNameIsIgnoredAfterItsFirstRow() throws {
        let limits = try parsedLimits("variant-repeated-model.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits[2].window?.utilization == 0)
    }

    @Test func malformedLinesAreSkipped() throws {
        let limits = try parsedLimits("variant-malformed-lines.stream.jsonl")

        #expect(limits.map(\.id) == ["session", "weekly", "model:Fable"])
        #expect(limits.map(\.window?.utilization) == [14, 36, 0])
    }

    @Test func nullRateLimitsAreReportedAsSuch() throws {
        let report = ClaudeParser.usageReport(from: try Fixtures.data("variant-rate-limits-null.stream.jsonl"))

        #expect(report == .rateLimitsNull)
    }

    @Test func loggedOutOutputHasNoReport() throws {
        let report = ClaudeParser.usageReport(from: try Fixtures.data("usage-logged-out.stream.jsonl"))

        #expect(report == .missing)
    }

    /// A renamed `kind` must not look like "no window".
    @Test(arguments: ["variant-wrong-type.stream.jsonl", "variant-no-recognised-row.stream.jsonl"])
    func schemaMismatchIsUnexpected(fixture: String) throws {
        expectUnexpected(ClaudeParser.usageReport(from: try Fixtures.data(fixture)))
    }

    /// Each line breaks one schema rule of the report and is valid otherwise.
    @Test(arguments: [
        #"{"type":"assistant","usage_report":"report"}"#,
        #"{"type":"assistant","usage_report":{}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":[]}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":{}}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":["session"]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"session","percent":true,"resets_at":null}]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"weekly_all","percent":36,"resets_at":1791334799}]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"weekly_all","percent":36,"resets_at":"Oct 7 at 3am"}]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":{"model":{}}}]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":{"model":{"display_name":""}}}]}}}"#,
        #"{"type":"assistant","usage_report":{"rate_limits":{"limits":[{"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":{"model":"Fable"}}]}}}"#,
    ])
    func brokenSchemaRuleIsUnexpected(line: String) {
        expectUnexpected(ClaudeParser.usageReport(from: Data(line.utf8)))
    }
}

private func expectUnexpected(_ report: UsageReport, sourceLocation: SourceLocation = #_sourceLocation) {
    guard case .unexpected = report else {
        Issue.record("expected an unexpected response, got \(report)", sourceLocation: sourceLocation)
        return
    }
}

/// Parses a fixture and fails the test unless it yields limits.
private func parsedLimits(
    _ fixture: String, sourceLocation: SourceLocation = #_sourceLocation
) throws -> [Limit] {
    let report = ClaudeParser.usageReport(from: try Fixtures.data(fixture))
    guard case .limits(let limits) = report else {
        Issue.record("expected limits, got \(report)", sourceLocation: sourceLocation)
        return []
    }
    return limits
}

private func expectDate(
    _ actual: Date?, near secondsSince1970: TimeInterval,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let actual else {
        Issue.record("expected a date, got nil", sourceLocation: sourceLocation)
        return
    }
    #expect(
        abs(actual.timeIntervalSince1970 - secondsSince1970) < 0.001,
        "\(actual) is not \(date(secondsSince1970))", sourceLocation: sourceLocation
    )
}
