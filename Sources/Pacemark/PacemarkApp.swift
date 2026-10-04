import PacemarkClaude
import PacemarkKit
import SwiftUI

/// The shell: the one place that names a provider. Everything else lives in
/// PacemarkKit.
@main
struct PacemarkApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel(provider: ClaudeProvider())
        _model = State(initialValue: model)
        Driver.start(model)
    }

    var body: some Scene {
        MenuBarExtra {
            // MenuBarExtra rebuilds the view on every open.
            DropdownView(model: model)
                .onAppear { model.dropdownOpened() }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
