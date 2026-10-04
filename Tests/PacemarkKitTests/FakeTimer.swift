import Foundation

/// The app model's query timer under the test's control. It records every
/// time the model arms it and fires only when the test says so.
///
/// Every finished query re-arms the timer, so `armed()` also tells a test
/// that the query it triggered has finished.
@MainActor final class FakeTimer {
    private var armings: [TimeInterval] = []
    private var consumed = 0
    private var waiter: CheckedContinuation<TimeInterval, Never>?
    /// Sleeps that are neither fired nor cancelled yet, by arming order.
    private var sleepers: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextID = 0

    /// What the model calls instead of `Task.sleep`.
    func sleep(_ seconds: TimeInterval) async throws {
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = continuation
                armings.append(seconds)
                handOutArming()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Waits until the model arms the timer (or returns an arming the test
    /// hasn't looked at yet), and says for how many seconds. Gives NaN when
    /// the test's time limit cancels the wait.
    func armed() async -> TimeInterval {
        if consumed < armings.count {
            consumed += 1
            return armings[consumed - 1]
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor in self.giveUpWaiting() }
        }
    }

    /// Lets the most recently armed timer go off.
    func fire() {
        guard let id = sleepers.keys.max() else { return }
        sleepers.removeValue(forKey: id)?.resume()
    }

    private func cancel(_ id: Int) {
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func giveUpWaiting() {
        waiter?.resume(returning: .nan)
        waiter = nil
    }

    private func handOutArming() {
        guard let waiter else { return }
        self.waiter = nil
        consumed += 1
        waiter.resume(returning: armings[consumed - 1])
    }
}
