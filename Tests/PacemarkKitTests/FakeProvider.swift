import Foundation
import PacemarkKit
import Testing

/// A provider that answers each query with the next scripted result.
@MainActor final class FakeProvider: Provider {
    let id = "fake"
    let name = "Fake"
    private var results: [FetchResult]
    /// How many queries it answered.
    private(set) var fetchCount = 0

    init(_ results: FetchResult...) {
        self.results = results
    }

    func fetch() async -> FetchResult {
        fetchCount += 1
        guard !results.isEmpty else {
            Issue.record("Query \(fetchCount) has no scripted result")
            return .unavailable
        }
        return results.removeFirst()
    }
}

/// A model whose first query, at `now`, got `result`. Its timer is under
/// the test's control and never fires.
func model(
    after result: FetchResult, settings: PacemarkKit.Settings = PacemarkKit.Settings(), at now: Date
) async -> AppModel {
    let timer = FakeTimer()
    let model = AppModel(provider: FakeProvider(result), clock: { now }, sleep: { try await timer.sleep($0) })
    model.settings = settings
    model.launch()
    _ = await timer.armed()
    return model
}
