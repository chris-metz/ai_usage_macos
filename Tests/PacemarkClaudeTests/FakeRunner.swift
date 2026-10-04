import Foundation
import Synchronization

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
}
