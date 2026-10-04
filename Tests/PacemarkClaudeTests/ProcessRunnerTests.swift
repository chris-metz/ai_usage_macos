import Foundation
import Testing

@testable import PacemarkClaude

@Suite struct ProcessRunnerTests {
    @Test func echoExitsWithItsOutput() async throws {
        let result = try await ProcessRunner().run(command("/bin/echo", "hello"))

        #expect(result == .exited(status: 0, stdout: Data("hello\n".utf8), stderr: Data()))
    }

    @Test func nonZeroExitStatusIsReported() async throws {
        let result = try await ProcessRunner().run(command("/bin/sh", "-c", "echo oops >&2; exit 3"))

        #expect(result == .exited(status: 3, stdout: Data(), stderr: Data("oops\n".utf8)))
    }

    /// Far more than a pipe buffer on both pipes: without concurrent reads
    /// the child would block on a full pipe and never exit.
    @Test func largeOutputOnBothPipesDoesNotDeadlock() async throws {
        let size = 1_000_000
        let script = "/bin/dd if=/dev/zero bs=1000 count=1000 2>/dev/null; /bin/dd if=/dev/zero bs=1000 count=1000 >&2 2>/dev/null"
        let result = try await ProcessRunner().run(command("/bin/sh", "-c", "\(script)"))

        guard case .exited(let status, let stdout, let stderr) = result else {
            Issue.record("expected an exit, got \(result)")
            return
        }
        #expect(status == 0)
        #expect(stdout.count == size)
        #expect(stderr.count == size)
    }

    @Test func missingExecutableThrows() async throws {
        let directory = try TemporaryDirectory()

        await #expect(throws: (any Error).self) {
            try await ProcessRunner().run(command(directory.url.appending(path: "missing").path(percentEncoded: false)))
        }
    }

    @Test func environmentIsExactlyTheGivenOne() async throws {
        let result = try await ProcessRunner().run(command("/usr/bin/env", environment: ["PACEMARK_TEST": "1"]))

        #expect(result == .exited(status: 0, stdout: Data("PACEMARK_TEST=1\n".utf8), stderr: Data()))
    }

    @Test func runsInTheGivenWorkingDirectory() async throws {
        let directory = try TemporaryDirectory()
        let result = try await ProcessRunner().run(command("/bin/pwd", "-P", workingDirectory: directory.url))

        let expected = try #require(realpath(directory.url.path(percentEncoded: false), nil))
        defer { free(expected) }
        #expect(result == .exited(status: 0, stdout: Data((String(cString: expected) + "\n").utf8), stderr: Data()))
    }

    @Test func readsStandardInputFromTheGivenFile() async throws {
        let directory = try TemporaryDirectory()
        let input = directory.url.appending(path: "input.txt")
        try Data("from stdin\n".utf8).write(to: input)
        var cat = command("/bin/cat")
        cat.standardInput = input

        let result = try await ProcessRunner().run(cat)

        #expect(result == .exited(status: 0, stdout: Data("from stdin\n".utf8), stderr: Data()))
    }

    @Test func timeoutEndsTheProcessWithSIGTERM() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await ProcessRunner().run(command("/bin/sleep", "10", timeout: .milliseconds(200)))

        #expect(result == .timedOut)
        // Well before the default 2 s grace period: SIGTERM ended it.
        #expect(clock.now - start < .seconds(1.5))
    }

    @Test func processIgnoringSIGTERMGetsSIGKILLAfterTheGracePeriod() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let runner = ProcessRunner(killGracePeriod: .milliseconds(500))
        let result = try await runner.run(
            command("/bin/sh", "-c", "trap '' TERM; exec /bin/sleep 10", timeout: .milliseconds(200))
        )

        #expect(result == .timedOut)
        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(700))
        #expect(elapsed < .seconds(5))
    }
}

/// A command with an empty environment, the temp directory, stdin
/// `/dev/null` and a timeout generous enough for system binaries.
private func command(
    _ executable: String, _ arguments: String..., environment: [String: String] = [:],
    workingDirectory: URL = FileManager.default.temporaryDirectory,
    timeout: Duration = .seconds(10)
) -> Command {
    Command(
        executable: URL(filePath: executable),
        arguments: arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        standardInput: URL(filePath: "/dev/null"),
        timeout: timeout
    )
}
