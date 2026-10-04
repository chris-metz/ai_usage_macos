import Foundation

/// The version number `claude --version` leads with, e.g. 2.1.289.
nonisolated struct ClaudeVersion: Equatable, Sendable {
    /// As written in the output, e.g. `2.1.289`.
    let text: String
    let components: [Int]

    /// The oldest Claude Code whose `/usage` Pacemark can read.
    static let minimum = ClaudeVersion(text: "2.1.283", components: [2, 1, 283])

    /// Older than `minimum`, compared component-wise with missing components as 0.
    var isTooOld: Bool {
        let count = max(components.count, Self.minimum.components.count)
        let padded = { (components: [Int]) in components + Array(repeating: 0, count: count - components.count) }
        return padded(components).lexicographicallyPrecedes(padded(Self.minimum.components))
    }
}

nonisolated extension ClaudeParser {
    /// The leading `\d+(\.\d+)*` of the `claude --version` stdout, e.g.
    /// `2.1.289 (Claude Code)`; nil when there is none.
    static func version(from stdout: Data) -> ClaudeVersion? {
        let output = String(decoding: stdout, as: UTF8.self).drop(while: \.isWhitespace)
        guard let match = output.prefixMatch(of: /[0-9]+(\.[0-9]+)*/) else { return nil }
        let text = String(match.output.0)
        let components = text.split(separator: ".").compactMap { Int($0) }
        // A component too large for Int doesn't count as a version.
        guard components.count == text.split(separator: ".").count else { return nil }
        return ClaudeVersion(text: text, components: components)
    }
}
