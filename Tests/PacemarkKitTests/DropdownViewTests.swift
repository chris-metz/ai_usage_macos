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

    @Test func dropdownStale() async {
        // The last success was 23 min before `now`; the query at `now` failed.
        var time = now - 23 * 60
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(.limits(threeLimits), .unavailable), clock: { time },
                             sleep: { try await timer.sleep($0) })
        model.launch()
        _ = await timer.armed()
        time = now
        timer.fire()
        _ = await timer.armed()

        expectViewSnapshot(dropdown(model), width: 300)
    }

    @Test func dropdownLoading() {
        let model = AppModel(provider: SilentProvider(), clock: { now })
        model.launch()

        expectViewSnapshot(dropdown(model), width: 300)
    }

    @Test func dropdownNoValues() async {
        let view = await dropdown(after: .unavailable)

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownAllLimitsHidden() async {
        let hidden = ["fake/session", "fake/weekly", "fake/model:Fable"]
        let view = await dropdown(after: .limits(threeLimits), settings: PacemarkKit.Settings(hiddenLimits: hidden))

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownSomeLimitsHidden() async {
        let view = await dropdown(after: .limits(threeLimits), settings: PacemarkKit.Settings(hiddenLimits: ["fake/weekly"]))

        expectViewSnapshot(view, width: 300)
    }

    // The four problems of the Claude provider, with the appendix's texts.

    @Test func dropdownClaudeCodeNotFound() async {
        let view = await dropdown(after: .problem(Problem(
            heading: "Claude Code not found",
            message: "Pacemark reads your limits through Claude Code. Install it and log in.",
            link: ProblemLink(title: "Install Claude Code", url: URL(string: "https://code.claude.com/docs/en/setup")!)
        )))

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownClaudeCodeTooOld() async {
        let view = await dropdown(after: .problem(Problem(
            heading: "Claude Code is too old",
            message: "Pacemark needs version 2.1.283 or later (found 2.1.280). Run `claude update` in Terminal.",
            link: nil
        )))

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownNotLoggedIn() async {
        let view = await dropdown(after: .problem(Problem(
            heading: "Claude Code is not logged in",
            message: "Run `claude` in Terminal and log in.",
            link: nil
        )))

        expectViewSnapshot(view, width: 300)
    }

    @Test func dropdownCantReadYourLimits() async {
        let view = await dropdown(after: .problem(Problem(
            heading: "Can't read your limits",
            message: "Claude changed how it reports limits. A newer version of Pacemark should fix this.",
            link: ProblemLink(title: "Open on GitHub", url: URL(string: "https://github.com/chris-metz/pacemark")!)
        )))

        expectViewSnapshot(view, width: 300)
    }

    /// Over, on and under pace at `now`.
    private let threeLimits = [
        session(utilization: 71, resetsAt: "2026-10-04T12:00:00Z"),
        weekly(utilization: 63, resetsAt: "2026-10-07T00:59:59.880Z"),
        fable(utilization: 22, resetsAt: "2026-10-07T01:00:00Z"),
    ]

    /// The dropdown after a query that delivered `limits`, at `now`.
    private func dropdown(_ limits: [Limit]) async -> some View {
        await dropdown(after: .limits(limits))
    }

    /// The dropdown after the first query, which answered `result` at `now`.
    private func dropdown(after result: FetchResult, settings: PacemarkKit.Settings = PacemarkKit.Settings()) async -> some View {
        let timer = FakeTimer()
        let model = AppModel(provider: FakeProvider(result), clock: { now },
                             sleep: { try await timer.sleep($0) })
        model.settings = settings
        model.launch()
        _ = await timer.armed()
        return dropdown(model)
    }

    private func dropdown(_ model: AppModel) -> some View {
        DropdownView(model: model)
            .environment(\.timeZone, berlin)
            .environment(\.locale, enDE)
    }
}

/// A provider whose query never finishes while a test runs.
nonisolated struct SilentProvider: Provider {
    let id = "silent"
    let name = "Silent"

    func fetch() async -> FetchResult {
        try? await Task.sleep(for: .seconds(3600))
        return .unavailable
    }
}

func fable(utilization: Double, resetsAt: String) -> Limit {
    Limit(id: "model:Fable", title: "Fable limit", windowLength: 7 * 86400,
          window: ActiveWindow(utilization: utilization, resetsAt: date(resetsAt)))
}
