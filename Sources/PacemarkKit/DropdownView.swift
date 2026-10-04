import AppKit
import SwiftUI

/// The content of the menu bar item's window (§3): the limit rows or what
/// stands in for them, and a footer with the stale line, Settings… and Quit.
/// Its state lives in the model, because `MenuBarExtra` discards view state
/// on close.
public struct DropdownView: View {
    let model: AppModel

    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    /// Closes the dropdown.
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let display = model.display
        VStack(alignment: .leading, spacing: 12) {
            content(display.dropdown)
                .padding(.horizontal, 14)
            Divider()
            footer(staleLine: display.staleLine)
                .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
        // MenuBarExtra rebuilds the view on every open.
        .onAppear { model.dropdownOpened() }
    }

    @ViewBuilder private func content(_ content: DropdownContent) -> some View {
        switch content {
        case .loading:
            Text("Loading…")
                .foregroundStyle(.secondary)
        case .problem(let problem):
            ProblemView(problem: problem)
        case .limits(let limits):
            ForEach(limits) { limit in
                LimitRow(display: limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale))
            }
        case .noValues:
            ProblemView(problem: Problem(
                heading: "Can't load your limits right now",
                message: "Trying again shortly.",
                link: nil
            ))
        }
    }

    private func footer(staleLine: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let staleLine {
                Text(staleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Settings…") {
                    dismiss()
                    openWindow.openSettings()
                }
                .keyboardShortcut(",")
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

/// A heading, a Markdown message and an optional link, in place of the
/// limit rows (§3 Other contents). The message is selectable so a command
/// like `claude update` can be copied.
private struct ProblemView: View {
    let problem: Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.heading)
                .font(.system(size: 13, weight: .semibold))
            Text(markdown(problem.message))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let link = problem.link {
                Link(link.title, destination: link.url)
                    .padding(.top, 4)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The message with inline Markdown such as `code`; as plain text if it
    /// doesn't parse.
    private func markdown(_ message: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message, options: options)) ?? AttributedString(message)
    }
}
