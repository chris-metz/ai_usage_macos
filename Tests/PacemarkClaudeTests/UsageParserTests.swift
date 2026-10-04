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

    @Test func loggedOutOutputHasNoReport() throws {
        let report = ClaudeParser.usageReport(from: try Fixtures.data("usage-logged-out.stream.jsonl"))

        #expect(report == .missing)
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
