import Foundation
import PacemarkKit
import SwiftUI
import Testing

/// The dropdown (§3), rendered in light and dark at a fixed `now` in Berlin.
@Suite struct DropdownViewTests {
    @Test func dropdownOverOnAndUnderPace() async {
        let view = await dropdown([
            session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
            weekly(utilization: 63, resetsAt: "2026-10-07T00:59:59.880Z"),
            fable(utilization: 22, resetsAt: "2026-10-07T01:00:00Z"),
        ])

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownHighAndExhausted() async {
        let view = await dropdown([
            session(utilization: 93, resetsAt: "2026-10-04T12:00:00Z"),
            weekly(utilization: 100, resetsAt: "2026-10-07T00:59:59.880Z"),
            fable(utilization: 140, resetsAt: "2026-10-07T01:00:00Z"),
        ])

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownNoSessionWindow() async {
        let view = await dropdown([
            Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil),
            weekly(utilization: 36, resetsAt: "2026-10-07T00:59:59.880Z"),
            fable(utilization: 0, resetsAt: "2026-10-07T01:00:00Z"),
        ])

        expectViewSnapshot(view, width: 300)
    }

    /// The dropdown after a query that delivered `limits`, at `now`.
    private func dropdown(_ limits: [Limit]) async -> some View {
        let model = AppModel(provider: FakeProvider(.limits(limits)), clock: { now })
        await model.query()
        return DropdownView(model: model)
            .environment(\.timeZone, berlin)
            .environment(\.locale, enDE)
    }
}

func fable(utilization: Double, resetsAt: String) -> Limit {
    Limit(id: "model:Fable", title: "Fable limit", windowLength: 7 * 86400,
          window: ActiveWindow(utilization: utilization, resetsAt: date(resetsAt)))
}
