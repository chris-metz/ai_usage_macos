import Foundation

/// Runs a process with Foundation's `Process`, off the main actor.
nonisolated struct ProcessRunner: CommandRunner {
    /// Time between SIGTERM and SIGKILL after a timeout.
    var killGracePeriod: Duration = .seconds(2)

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
        let output = Task { await readToEnd(stdout.fileHandleForReading) }
        let errors = Task { await readToEnd(stderr.fileHandleForReading) }
        let pid = process.processIdentifier
        let killer = Task { [timeout = command.timeout, grace = killGracePeriod] () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            kill(pid, SIGTERM)
            try? await Task.sleep(for: grace)
            if !Task.isCancelled { kill(pid, SIGKILL) }
            return true
        }

        for await _ in exit {}
        killer.cancel()
        if await killer.value { return .timedOut }
        return .exited(status: process.terminationStatus, stdout: await output.value, stderr: await errors.value)
    }
}

/// Reads a pipe to its end on a dispatch thread, so the blocking read
/// doesn't hold a thread of the cooperative pool.
private nonisolated func readToEnd(_ handle: FileHandle) async -> Data {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
        }
    }
}
