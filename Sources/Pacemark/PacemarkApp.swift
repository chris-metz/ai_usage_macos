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
        model.launch()
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
