import Foundation
import PacemarkKit
import Testing

/// The app model with a scripted provider and a fixed clock.
@Suite struct AppModelTests {
    @Test func showsTheGlyphAloneBeforeTheFirstResult() {
        let model = AppModel(provider: FakeProvider())

        #expect(model.menuBarDisplay == MenuBarDisplay(percentText: nil, accessibilityText: "Pacemark"))
    }

    @Test func showsTheSessionLimitAfterAQuery() async {
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), clock: { beforeTheResets })

        await model.query()

        #expect(model.menuBarDisplay == MenuBarDisplay(percentText: "14%", accessibilityText: "Session limit 14%"))
    }

    @Test func aSessionLimitWithNoWindowShows0Percent() async {
        let session = Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)
        let model = AppModel(provider: FakeProvider(.limits([session])))

        await model.query()

        #expect(model.menuBarDisplay == MenuBarDisplay(percentText: "0%", accessibilityText: "Session limit 0%"))
    }

    @Test func utilizationShowsRoundedAndAtMost100Percent() async {
        let resetsAt = Date(timeIntervalSince1970: 1_790_000_000)
        let model = AppModel(provider: FakeProvider(
            .limits([Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
                           window: ActiveWindow(utilization: 71.4, resetsAt: resetsAt))]),
            .limits([Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
                           window: ActiveWindow(utilization: 140, resetsAt: resetsAt))])
        ), clock: { beforeTheResets })

        await model.query()
        #expect(model.menuBarDisplay.percentText == "71%")

        await model.query()
        #expect(model.menuBarDisplay.percentText == "100%")
    }

    @Test func aFailedQueryKeepsTheLastLimits() async {
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .unavailable))

        await model.query()
        await model.query()

        #expect(model.limits == claudeLimits)
    }

    @Test func nowIsTheClocksTimeAtLaunchAndAfterEveryQuery() async {
        var time = Date(timeIntervalSince1970: 1_000)
        let model = AppModel(provider: FakeProvider(.unavailable), clock: { time })
        #expect(model.now == Date(timeIntervalSince1970: 1_000))

        time = Date(timeIntervalSince1970: 2_000)
        await model.query()

        #expect(model.now == Date(timeIntervalSince1970: 2_000))
    }

    @Test func openingTheDropdownUpdatesNow() {
        var time = Date(timeIntervalSince1970: 1_000)
        let model = AppModel(provider: FakeProvider(), clock: { time })

        time = Date(timeIntervalSince1970: 2_000)
        model.dropdownOpened()

        #expect(model.now == Date(timeIntervalSince1970: 2_000))
    }

    @Test func theMenuBarShows0PercentOnceTheResetTimeHasPassed() async {
        var time = beforeTheResets
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), clock: { time })
        await model.query()

        time = Date(timeIntervalSince1970: 1_790_000_001)
        model.dropdownOpened()

        #expect(model.menuBarDisplay == MenuBarDisplay(percentText: "0%", accessibilityText: "Session limit 0%"))
    }
}

/// Inside every window of `claudeLimits`.
let beforeTheResets = Date(timeIntervalSince1970: 1_789_990_000)

/// Like the `usage.stream.jsonl` fixture: session 14%, weekly 36%, Fable 0%.
let claudeLimits = [
    Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
          window: ActiveWindow(utilization: 14, resetsAt: Date(timeIntervalSince1970: 1_790_000_000))),
    Limit(id: "weekly", title: "Weekly limit", windowLength: 7 * 86400,
          window: ActiveWindow(utilization: 36, resetsAt: Date(timeIntervalSince1970: 1_790_300_000))),
    Limit(id: "model:Fable", title: "Fable limit", windowLength: 7 * 86400,
          window: ActiveWindow(utilization: 0, resetsAt: Date(timeIntervalSince1970: 1_790_300_000))),
]
