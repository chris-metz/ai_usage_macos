import Foundation
import PacemarkKit

/// The persistent errors of the Claude provider, worded as in the spec's appendix.
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

    static let notLoggedIn = Problem(
        heading: "Claude Code is not logged in",
        message: "Run `claude` in Terminal and log in.",
        link: nil
    )

    static let unexpectedResponse = Problem(
        heading: "Can't read your limits",
        message: "Claude changed how it reports limits. A newer version of Pacemark should fix this.",
        link: ProblemLink(title: "Open on GitHub", url: URL(string: "https://github.com/chris-metz/pacemark")!)
    )
}
