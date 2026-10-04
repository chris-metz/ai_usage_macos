import AppKit
import SwiftUI

/// The content of the menu bar item's window (§3): one line per limit and a
/// footer with Quit. Its state lives in the model, because `MenuBarExtra`
/// discards view state on close.
public struct DropdownView: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.limits) { limit in
                HStack {
                    Text(limit.title)
                    Spacer()
                    Text(percentText(limit))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300)
    }
}
