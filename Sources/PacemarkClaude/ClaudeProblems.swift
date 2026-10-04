import Foundation
import PacemarkKit

/// The persistent errors of the Claude provider, worded as in the spec's appendix.
nonisolated extension Problem {
    static let unexpectedResponse = Problem(
        heading: "Can't read your limits",
        message: "Claude changed how it reports limits. A newer version of Pacemark should fix this.",
        link: ProblemLink(title: "Open on GitHub", url: URL(string: "https://github.com/chris-metz/pacemark")!)
    )
}
