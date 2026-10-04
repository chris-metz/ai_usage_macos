import AppKit
import SwiftUI

/// Quits Pacemark at once, without asking, also with ⌘Q (§5). The dropdown
/// and the settings window each have one.
struct QuitButton: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Button(title) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Pacemark's repository: the settings window's `GitHub` link, and where a
/// problem may send the user.
public nonisolated let repositoryURL = URL(string: "https://github.com/chris-metz/pacemark")!
