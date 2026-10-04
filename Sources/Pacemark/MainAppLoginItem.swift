import PacemarkKit
import ServiceManagement

/// Pacemark itself as a login item, the one place that names
/// `SMAppService`. It lives in the shell so no test can reach it: reading
/// the status from a copy outside `/Applications` can move the real login
/// item there (§4). `OpenAtLogin` only lets the installed copy use it.
struct MainAppLoginItem: LoginItem {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
