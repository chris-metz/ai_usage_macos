import AppKit
import SwiftUI

/// The content of the menu bar item's window (§3): one row per limit and a
/// footer with Quit. Its state lives in the model, because `MenuBarExtra`
/// discards view state on close.
public struct DropdownView: View {
    let model: AppModel

    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.limits) { limit in
                LimitRow(display: limitDisplay(limit, now: model.now, timeZone: timeZone, locale: locale))
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
        // MenuBarExtra rebuilds the view on every open.
        .onAppear { model.dropdownOpened() }
    }
}
