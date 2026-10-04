import PacemarkKit

/// A provider that answers each query with the next scripted result.
@MainActor final class FakeProvider: Provider {
    let id = "fake"
    let name = "Fake"
    private var results: [FetchResult]

    init(_ results: FetchResult...) {
        self.results = results
    }

    func fetch() async -> FetchResult {
        results.removeFirst()
    }
}
