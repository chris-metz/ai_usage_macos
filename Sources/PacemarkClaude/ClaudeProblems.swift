import Foundation
import PacemarkKit

/// The persistent errors of the Claude provider, worded for the dropdown.
nonisolated extension Problem {
    static let claudeCodeNotFound = Problem(
        heading: "Claude Code not found",
        message: "Pacemark reads your limits through Claude Code. Install it and log in.",
        link: ProblemLink(title: "Install Claude Code", url: URL(string: "https://code.claude.com/docs/en/setup")!)
    )

    static func claudeCodeTooOld(found version: ClaudeVersion) -> Problem {
        Problem(
            heading: "Claude Code is too old",
            message: "Pacemark needs version \(ClaudeVersion.minimum.text) or later (found \(version.text)). Run `claude update` in Terminal.",
            link: nil
        )
    }
}
