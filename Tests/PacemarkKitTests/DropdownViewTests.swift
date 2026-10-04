import PacemarkKit
import Testing

/// The dropdown (§3), rendered in light and dark.
@Suite struct DropdownViewTests {
    @Test func dropdownLimits() async {
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()

        expectViewSnapshot(DropdownView(model: model), width: 300)
    }
}
