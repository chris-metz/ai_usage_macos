import AppKit
import Network
import PacemarkKit

/// Connects the app model to the real world (§6.4): launch, a tick on every
/// full minute, wake from sleep and the network path. It runs for the app's
/// lifetime; the model decides what each event means.
enum Driver {
    static func start(_ model: AppModel) {
        model.launch()

        Task {
            while !Task.isCancelled {
                let now = Date()
                try? await Task.sleep(for: .seconds(nextFullMinute(after: now).timeIntervalSince(now)))
                model.minuteTick()
            }
        }

        Task {
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                model.wake()
            }
        }

        // Yields the current path at once, then every change.
        Task {
            for await path in NWPathMonitor() {
                model.networkChanged(isSatisfied: path.status == .satisfied)
            }
        }
    }
}
