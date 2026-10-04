import Foundation

/// One process to run, spelled out completely so tests can assert it.
nonisolated struct Command: Equatable, Sendable {
    var executable: URL
    var arguments: [String]
    /// The complete environment; nothing is inherited.
    var environment: [String: String]
    var workingDirectory: URL
    var standardInput: URL
    /// After this, SIGTERM to the process group, and SIGKILL a grace period
    /// later.
    var timeout: Duration
}

nonisolated extension Command {
    /// Where every command's environment starts, since nothing is
    /// inherited: `HOME`, `USER` and the system `PATH`.
    static func baseEnvironment(homeDirectory: URL, userName: String) -> [String: String] {
        [
            "HOME": homeDirectory.pathWithoutTrailingSlash,
            "USER": userName,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    }

    /// Every command's stdin, so nothing waits for input.
    static let noInput = URL(filePath: "/dev/null")
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

nonisolated extension CommandRunner {
    /// Runs `command` and logs its exit status, duration and stderr, the
    /// latter cut to 2 KB; nil when it couldn't start.
    func runLogged(_ command: Command) async -> CommandResult? {
        let name = "\(command.executable.lastPathComponent) \(command.arguments.last ?? "")"
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let result = try await run(command)
            let duration = clock.now - start
            switch result {
            case .exited(let status, _, let stderr):
                let stderrText = String(decoding: stderr.prefix(2048), as: UTF8.self)
                claudeLog.log(
                    "\(name, privacy: .public) exited with status \(status) after \(duration, privacy: .public); stderr: \(stderrText, privacy: .public)"
                )
            case .timedOut:
                claudeLog.error("\(name, privacy: .public) timed out after \(duration, privacy: .public)")
            }
            return result
        } catch {
            claudeLog.error("\(name, privacy: .public) could not start: \(error, privacy: .public)")
            return nil
        }
    }
}

nonisolated extension URL {
    /// The path without a trailing slash, as a shell would set `HOME`.
    var pathWithoutTrailingSlash: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
