import Foundation
import Observation
import ServiceManagement

/// The app's own login item. The app passes `SMAppService.mainApp`; tests
/// pass a fake and never touch the real one.
public protocol LoginItem {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings > General > Login Items.
    func openSystemSettings()
}

/// The `Open at Login` switch of the settings window (§4). The login item
/// is the only truth; Pacemark stores nothing of its own about it and never
/// adds itself (§5).
///
/// Only the copy at `/Applications/Pacemark.app` touches the login item.
/// Any other copy never reads its status, because reading it from another
/// copy can move the login item there.
@Observable public final class OpenAtLogin {
    public enum State: Equatable {
        /// The login item is enabled.
        case on
        /// The login item isn't enabled, or its status hasn't been read yet.
        case off
        /// The user turned the login item off in System Settings
        /// (`.requiresApproval`), where switching on changes nothing. The
        /// switch shows off, with a note and a way to System Settings.
        case turnedOffInSystemSettings
        /// This copy isn't `/Applications/Pacemark.app`: the switch is
        /// disabled.
        case notInApplications
    }

    /// What the switch shows.
    public private(set) var state: State

    /// Whether the switch shows on.
    public var isOn: Bool { state == .on }

    @ObservationIgnored private let loginItem: any LoginItem
    /// Whether this copy may touch the login item.
    @ObservationIgnored private let isInstalledCopy: Bool

    /// - Parameter bundleURL: Where this copy of Pacemark lives.
    public init(loginItem: any LoginItem, bundleURL: URL) {
        self.loginItem = loginItem
        isInstalledCopy = bundleURL.standardizedFileURL.pathComponents == ["/", "Applications", "Pacemark.app"]
        state = isInstalledCopy ? .off : .notInApplications
    }

    /// Reads the login item's status again.
    public func refresh() {
        guard isInstalledCopy else { return }
        state = switch loginItem.status {
        case .enabled: .on
        case .requiresApproval: .turnedOffInSystemSettings
        default: .off
        }
    }

    /// The user flipped the switch: on registers the login item, off
    /// unregisters it. Nothing else does either. Afterwards, and after a
    /// failure, the switch shows the status read again.
    public func switchTo(_ isOn: Bool) {
        guard isInstalledCopy else { return }
        do {
            if isOn {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
            appLog.info("Open at Login turned \(isOn ? "on" : "off", privacy: .public)")
        } catch {
            appLog.error("Couldn't turn Open at Login \(isOn ? "on" : "off", privacy: .public): \(error, privacy: .public)")
        }
        refresh()
    }

    /// The link button below the `.requiresApproval` note.
    public func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }
}
