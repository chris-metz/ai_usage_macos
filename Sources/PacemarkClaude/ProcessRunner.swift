import Foundation
import Synchronization

/// Runs a process with Foundation's `Process`, off the main actor.
///
/// `Process` makes the child the leader of a new process group, so the
/// runner signals that group: the signals also reach whatever the child
/// started.
nonisolated struct ProcessRunner: CommandRunner {
    /// Time between SIGTERM and SIGKILL after a timeout.
    var killGracePeriod: Duration = .seconds(2)
    /// How long stdout and stderr may stay open after the child exits, held
    /// by a process it left behind, before the runner SIGKILLs the process
    /// group and stops reading.
    var outputGracePeriod: Duration = .seconds(1)

    @concurrent
    func run(_ command: Command) async throws -> CommandResult {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = try FileHandle(forReadingFrom: command.standardInput)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let (exit, exited) = AsyncStream.makeStream(of: Void.self)
        process.terminationHandler = { _ in exited.finish() }

        try process.run()

        // Drain both pipes while the process runs, so a full pipe buffer
        // can't block it.
        let output = PipeOutput(stdout)
        let errors = PipeOutput(stderr)
        let group = -process.processIdentifier
        let killer = Task { [timeout = command.timeout, grace = killGracePeriod] () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            kill(group, SIGTERM)
            try? await Task.sleep(for: grace)
            if !Task.isCancelled { kill(group, SIGKILL) }
            return true
        }

        for await _ in exit {}
        killer.cancel()
        let timedOut = await killer.value
        if await !bothReachEnd(output, errors, within: outputGracePeriod) {
            claudeLog.error("Output stayed open after the child exited: killed its process group")
            kill(group, SIGKILL)
        }
        let result = CommandResult.exited(
            status: process.terminationStatus, stdout: output.stop(), stderr: errors.stop()
        )
        return timedOut ? .timedOut : result
    }

    /// Whether every process holding the write ends of both pipes closes
    /// them within `limit`.
    private func bothReachEnd(_ output: PipeOutput, _ errors: PipeOutput, within limit: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { tasks in
            tasks.addTask {
                await output.end()
                await errors.end()
                return !Task.isCancelled
            }
            tasks.addTask {
                try? await Task.sleep(for: limit)
                return false
            }
            defer { tasks.cancelAll() }
            return await tasks.next() ?? false
        }
    }
}

/// What one pipe delivers, read as it arrives without blocking a thread.
private nonisolated final class PipeOutput: Sendable {
    private let handle: FileHandle
    private let collected = Mutex(Data())
    private let reachedEnd: AsyncStream<Never>

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        let (reachedEnd, continuation) = AsyncStream.makeStream(of: Never.self)
        self.reachedEnd = reachedEnd
        handle.readabilityHandler = { [self] handle in
            // One read of what is there; `FileHandle.read(upToCount:)` would
            // wait for the full count or the end.
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                collected.withLock { $0.append(contentsOf: buffer[..<count]) }
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                handle.readabilityHandler = nil
                continuation.finish()
            }
        }
    }

    /// Returns once every process holding the write end has closed it, or
    /// when the task is cancelled.
    func end() async {
        for await _ in reachedEnd {}
    }

    /// Stops reading and returns everything read so far.
    func stop() -> Data {
        handle.readabilityHandler = nil
        return collected.withLock { $0 }
    }
}
