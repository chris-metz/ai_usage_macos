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
