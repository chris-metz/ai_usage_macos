import Foundation

/// One process to run, spelled out completely so tests can assert it.
nonisolated struct Command: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    /// The complete environment; nothing is inherited.
    var environment: [String: String]
    var workingDirectory: URL
    var standardInput: URL
    /// After this, SIGTERM, and SIGKILL a grace period later.
    var timeout: Duration
}

nonisolated enum CommandResult: Equatable, Sendable {
    case exited(status: Int32, stdout: Data, stderr: Data)
    case timedOut
}

/// Runs a process. The real implementation is `ProcessRunner`.
nonisolated protocol CommandRunner: Sendable {
    /// Throws when the process can't be started.
    func run(_ command: Command) async throws -> CommandResult
}
