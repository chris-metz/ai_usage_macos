import Foundation
import PacemarkKit
import Testing

/// The app model with a scripted provider and a fixed clock.
@Suite struct AppModelTests {
    @Test func showsTheGlyphAloneBeforeTheFirstResult() {
        let model = AppModel(provider: FakeProvider())

        #expect(model.display.menuBar == MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark"))
    }

    @Test func showsTheSessionLimitAfterAQuery() async {
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), clock: { beforeTheResets },
                             sleep: { try await timer.sleep($0) })

        model.launch()
        _ = await timer.armed()

        #expect(model.display.menuBar == MenuBarDisplay(content: .percentage("14%", isRed: false, isDimmed: false), accessibilityText: "Session limit 14%"))
    }

    @Test func aSessionLimitWithNoWindowShows0Percent() async {
        let session = Limit(id: "session", title: "Session limit", windowLength: 5 * 3600, window: nil)
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits([session])), sleep: { try await timer.sleep($0) })

        model.launch()
        _ = await timer.armed()

        #expect(model.display.menuBar == MenuBarDisplay(content: .percentage("0%", isRed: false, isDimmed: false), accessibilityText: "Session limit 0%"))
    }

    @Test func utilizationShowsRoundedAndAtMost100Percent() async {
        let resetsAt = Date(timeIntervalSince1970: 1_790_000_000)
        var time = beforeTheResets
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(
            .limits([Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
                           window: ActiveWindow(utilization: 71.4, resetsAt: resetsAt))]),
            .limits([Limit(id: "session", title: "Session limit", windowLength: 5 * 3600,
                           window: ActiveWindow(utilization: 140, resetsAt: resetsAt))])
        ), clock: { time }, sleep: { try await timer.sleep($0) })

        model.launch()
        time += await timer.armed()
        #expect(model.display.menuBar.content == .percentage("71%", isRed: false, isDimmed: false))

        timer.fire()
        _ = await timer.armed()
        #expect(model.display.menuBar.content == .percentage("100%", isRed: true, isDimmed: false))
    }

    @Test func aTemporaryErrorAfterAProblemShowsNoValuesInsteadOfOldBars() async {
        var time = beforeTheResets
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .problem(notLoggedIn), .unavailable),
                             clock: { time }, sleep: { try await timer.sleep($0) })
        model.launch()
        time += await timer.armed()
        timer.fire()
        time += await timer.armed()

        timer.fire()
        _ = await timer.armed()

        #expect(model.display == Display(
            dropdown: .noValues,
            updateLine: nil,
            menuBar: MenuBarDisplay(content: .glyph(), accessibilityText: "Pacemark")
        ))
    }

    @Test func valuesTurnStaleAndDimWhileQueriesKeepFailing() async {
        var time = beforeTheResets
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits), .unavailable), clock: { time },
                             sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()
        time += 9 * 60
        timer.fire()
        _ = await timer.armed()
        #expect(model.display.updateLine == "Updated 9 min ago")

        time += 2 * 60
        model.minuteTick()

        #expect(model.display.updateLine == "Couldn't update · Last update 11 min ago")
        #expect(model.display.menuBar == MenuBarDisplay(
            content: .percentage("14%", isRed: false, isDimmed: true),
            accessibilityText: "Session limit 14%, not up to date"
        ))
    }

    @Test func nowIsTheClocksTimeAtLaunchAndAfterEveryQuery() async {
        var time = Date(timeIntervalSince1970: 1_000)
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.unavailable), clock: { time }, sleep: { try await timer.sleep($0) })
        #expect(model.now == Date(timeIntervalSince1970: 1_000))

        model.launch()
        time = Date(timeIntervalSince1970: 2_000)
        _ = await timer.armed()

        #expect(model.now == Date(timeIntervalSince1970: 2_000))
    }

    @Test func theMenuBarShows0PercentOnceTheResetTimeHasPassed() async {
        var time = beforeTheResets
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(claudeLimits)), clock: { time },
                             sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()

        time = Date(timeIntervalSince1970: 1_790_000_001)
        model.minuteTick()

        #expect(model.display.menuBar == MenuBarDisplay(content: .percentage("0%", isRed: false, isDimmed: false), accessibilityText: "Session limit 0%"))
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
