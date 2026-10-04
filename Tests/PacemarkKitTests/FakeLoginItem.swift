import PacemarkKit
import ServiceManagement

/// Stands in for `SMAppService.mainApp`, which no test may touch: reading
/// its status from a copy outside `/Applications` can move the human's real
/// login item (§4). Registering and unregistering change the status the
/// way the system would, unless a scripted error is thrown instead.
@MainActor final class FakeLoginItem: LoginItem {
    /// What the system reports. A test may change it to act as the user in
    /// System Settings.
    var systemStatus: SMAppService.Status
    /// Thrown by the next `register()` or `unregister()` instead of acting.
    var error: (any Error)?
    /// How often anything asked for the status.
    private(set) var statusReads = 0
    /// How often anything registered or unregistered.
    private(set) var changes = 0
    private(set) var openedSystemSettings = false

    init(_ status: SMAppService.Status = .notRegistered) {
        systemStatus = status
    }

    var status: SMAppService.Status {
        statusReads += 1
        return systemStatus
    }

    func register() throws {
        changes += 1
        if let error { throw error }
        systemStatus = .enabled
    }

    func unregister() throws {
        changes += 1
        if let error { throw error }
        systemStatus = .notRegistered
    }

    func openSystemSettings() {
        openedSystemSettings = true
    }
}
