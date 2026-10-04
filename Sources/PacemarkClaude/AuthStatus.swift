import Foundation

/// What `claude auth status` says about the login.
nonisolated enum AuthStatus: Equatable, Sendable {
    case loggedIn
    case loggedOut
}

extension ClaudeParser {
    /// Reads the JSON stdout of `claude auth status`; nil when it is
    /// unreadable. Only `loggedIn` counts, never the exit code.
    nonisolated static func authStatus(from stdout: Data) -> AuthStatus? {
        guard case .bool(let loggedIn)? = (try? JSONDecoder().decode(JSONValue.self, from: stdout))?["loggedIn"]
        else { return nil }
        return loggedIn ? .loggedIn : .loggedOut
    }
}
