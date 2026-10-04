import PacemarkKit
import Testing

/// The dropdown (§3), rendered in light and dark.
@Suite struct DropdownViewTests {
    @Test func dropdownLimits() async {
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)))
        await model.query()

        expectViewSnapshot(DropdownView(model: model), width: 300)
    }
}
