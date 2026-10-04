import Foundation
import Synchronization
import Testing

@testable import PacemarkClaude

/// A `CommandRunner` that records every command and answers from a script,
/// so no test ever runs the real `claude`.
nonisolated final class FakeRunner: CommandRunner {
    private let answer: @Sendable (Command) throws -> CommandResult
    private let recorded = Mutex<[Command]>([])

    init(_ answer: @escaping @Sendable (Command) throws -> CommandResult) {
        self.answer = answer
    }

    var commands: [Command] { recorded.withLock { $0 } }

    func run(_ command: Command) async throws -> CommandResult {
        recorded.withLock { $0.append(command) }
        return try answer(command)
    }

    /// The commands run with exactly these arguments.
    func commands(_ arguments: [String]) -> [Command] {
        commands.filter { $0.arguments == arguments }
    }
}

nonisolated extension FakeRunner {
    /// Answers by arguments, like `claude` would: `/usage` and `auth status`
    /// with the given results, `--version` with the version fixture. Without
    /// an `authStatus`, running `auth status` fails the test.
    static func claude(usage: CommandResult, authStatus: CommandResult? = nil) -> FakeRunner {
        FakeRunner { command in
            switch command.arguments {
            case ["auth", "status"]:
                guard let authStatus else {
                    Issue.record("auth status must not run here")
                    throw CocoaError(.executableNotLoadable)
                }
                return authStatus
            case ["--version"]:
                return try .fixture("version.txt")
            case let arguments where arguments.last == "/usage":
                return usage
            default:
                Issue.record("unexpected claude invocation \(command.arguments)")
                throw CocoaError(.executableNotLoadable)
            }
        }
    }
}

nonisolated extension CommandResult {
    /// A run that exited with `status` and printed a fixture on stdout.
    static func fixture(_ name: String, status: Int32 = 0) throws -> CommandResult {
        .exited(status: status, stdout: try Fixtures.data(name), stderr: Data())
    }
}
