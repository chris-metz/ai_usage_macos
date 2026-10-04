import Foundation
import PacemarkKit
import os

/// What the `usage_report` of a `/usage` run says.
nonisolated enum UsageReport: Equatable, Sendable {
    /// The limits in display order: session, weekly, then model limits.
    case limits([Limit])
    /// `rate_limits: null`.
    case rateLimitsNull
    /// No assistant line carries a `usage_report`, e.g. when logged out.
    case missing
    /// The report breaks the expected schema; the reason names the rule.
    case unexpected(reason: String)
}

/// Pure parsing of `claude` output.
nonisolated enum ClaudeParser {
    /// Reads the stream-json stdout of `claude -p … "/usage"`.
    static func usageReport(from stdout: Data) -> UsageReport {
        guard let report = firstUsageReport(in: stdout) else { return .missing }
        do throws(SchemaMismatch) {
            guard case .object = report else { throw SchemaMismatch("usage_report is not an object") }
            switch report["rate_limits"] {
            case .null?: return .rateLimitsNull
            case .object?: break
            default: throw SchemaMismatch("rate_limits is neither null nor an object")
            }
            guard case .array(let rows)? = report["rate_limits"]?["limits"] else {
                throw SchemaMismatch("rate_limits.limits is missing or not an array")
            }
            return .limits(try limits(from: rows))
        } catch {
            return .unexpected(reason: error.reason)
        }
    }

    /// The `usage_report` of the first assistant line that has a non-null one.
    private static func firstUsageReport(in stdout: Data) -> JSONValue? {
        let decoder = JSONDecoder()
        for line in stdout.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? decoder.decode(JSONValue.self, from: Data(line)),
                object["type"] == .string("assistant"),
                let report = object["usage_report"], report != .null
            else { continue }
            return report
        }
        return nil
    }

    /// The limits in the fixed order, with a session limit even when its row is missing.
    private static func limits(from rows: [JSONValue]) throws(SchemaMismatch) -> [Limit] {
        var session: Limit?
        var weekly: Limit?
        var models: [Limit] = []

        for row in rows {
            guard let limit = try limit(from: row) else { continue }
            if limit.id == "session", session == nil {
                session = limit
            } else if limit.id == "weekly", weekly == nil {
                weekly = limit
            } else if limit.id.hasPrefix("model:"), !models.contains(where: { $0.id == limit.id }) {
                models.append(limit)
            } else {
                claudeLog.info("Ignored a duplicate limits row for \(limit.id, privacy: .public)")
            }
        }

        guard session != nil || weekly != nil || !models.isEmpty else {
            throw SchemaMismatch("no recognised limits row")
        }
        return [session ?? sessionLimit(window: nil)] + (weekly.map { [$0] } ?? []) + models
    }

    /// The limit a row stands for, or nil for a row Pacemark ignores.
    private static func limit(from row: JSONValue) throws(SchemaMismatch) -> Limit? {
        guard case .object = row else { throw SchemaMismatch("a limits row is not an object") }
        switch row["kind"] {
        case .string("session"):
            return sessionLimit(window: try window(of: row))
        case .string("weekly_all"):
            return Limit(id: "weekly", title: "Weekly limit", windowLength: weeklyWindow, window: try window(of: row))
        case .string("weekly_scoped"):
            let model = row["scope"]?["model"]
            guard let model, model != .null else {
                claudeLog.info("Ignored a weekly_scoped row without a model scope")
                return nil
            }
            guard case .string(let name)? = model["display_name"], !name.isEmpty else {
                throw SchemaMismatch("a model scope has no non-empty display_name")
            }
            return Limit(id: "model:\(name)", title: "\(name) limit", windowLength: weeklyWindow, window: try window(of: row))
        case let kind:
            claudeLog.info("Ignored a limits row of kind \(String(describing: kind), privacy: .public)")
            return nil
        }
    }

    private static func sessionLimit(window: ActiveWindow?) -> Limit {
        Limit(id: "session", title: "Session limit", windowLength: sessionWindow, window: window)
    }

    /// The row's window, or nil when `percent` or `resets_at` is null or missing.
    private static func window(of row: JSONValue) throws(SchemaMismatch) -> ActiveWindow? {
        let utilization: Double?
        switch row["percent"] {
        case .number(let percent)?: utilization = percent
        case .null?, nil: utilization = nil
        default: throw SchemaMismatch("percent is neither a number nor null")
        }
        let resetsAt: Date?
        switch row["resets_at"] {
        case .string(let text)?:
            guard let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) else {
                throw SchemaMismatch("resets_at is not a parseable date")
            }
            resetsAt = date
        case .null?, nil: resetsAt = nil
        default: throw SchemaMismatch("resets_at is neither a string nor null")
        }
        guard let utilization, let resetsAt else { return nil }
        return ActiveWindow(utilization: utilization, resetsAt: resetsAt)
    }

    private static let sessionWindow: TimeInterval = 5 * 60 * 60
    private static let weeklyWindow: TimeInterval = 7 * 24 * 60 * 60
}

/// A broken schema rule, named for the log.
nonisolated struct SchemaMismatch: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}
