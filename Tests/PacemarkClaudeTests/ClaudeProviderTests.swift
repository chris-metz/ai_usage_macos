import Foundation
import PacemarkKit
import Testing

@testable import PacemarkClaude

/// The provider flow on a temp home with a fake `claude` that is never run:
/// a `FakeRunner` answers instead.
@Suite struct ClaudeProviderTests {
    let directory: TemporaryDirectory
    let home: URL
    let claude: URL

    init() throws {
        directory = try TemporaryDirectory()
        home = URL(filePath: directory.path + "/home", directoryHint: .isDirectory)
        claude = home.appending(path: ".local/bin/claude")
        try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path(percentEncoded: false))
    }

    /// A provider whose `claude` passes the version check, so `runner` only
    /// sees the steps after it. `ClaudeProviderBinaryTests` covers the check.
    func provider(_ runner: FakeRunner) -> ClaudeProvider {
        ClaudeProvider(
            homeDirectory: home,
            userName: "tester",
            locator: ClaudeLocator(
                homeDirectory: home, rootDirectory: directory.url.appending(path: "root"), userName: "tester",
                loginShell: URL(filePath: "/nonexistent/login-shell"), runner: runner),
            runner: CurrentVersionRunner(next: runner)
        )
    }

    @Test func runsUsageWithTheExactIsolatedInvocation() async throws {
        let runner = FakeRunner { _ in .exited(status: 0, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data()) }

        _ = await provider(runner).fetch()

        let command = try #require(runner.commands.first)
        #expect(runner.commands.count == 1)
        #expect(command.executable == claude)
        #expect(command.arguments == [
            "-p", "--no-session-persistence", "--strict-mcp-config", "--safe-mode", "--setting-sources", "",
            "--output-format", "stream-json", "--verbose", "/usage",
        ])
        #expect(command.environment == [
            "HOME": directory.path + "/home",
            "USER": "tester",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "DISABLE_AUTOUPDATER": "1",
            "DISABLE_TELEMETRY": "1",
        ])
        #expect(command.workingDirectory.pathComponents
            == home.pathComponents + ["Library", "Caches", "xyz.chrismetz.pacemark", "claude-cwd"])
        #expect(command.standardInput.path(percentEncoded: false) == "/dev/null")
        #expect(command.timeout == .seconds(30))
    }

    @Test func createsTheEmptyWorkingDirectoryIfMissing() async throws {
        let runner = FakeRunner { _ in .exited(status: 0, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data()) }

        _ = await provider(runner).fetch()

        let workingDirectory = try #require(runner.commands.first?.workingDirectory)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: workingDirectory.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func usageReportGivesTheLimits() async throws {
        let runner = FakeRunner { _ in .exited(status: 0, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data()) }

        let result = await provider(runner).fetch()

        guard case .limits(let limits) = result else {
            Issue.record("expected limits, got \(result)")
            return
        }
        #expect(limits.map(\.title) == ["Session limit", "Weekly limit", "Fable limit"])
        #expect(limits.map(\.window?.utilization) == [14, 36, 0])
    }

    @Test func nonZeroExitIsUnavailableEvenWithLimitsOnStdout() async throws {
        let runner = FakeRunner { _ in
            .exited(status: 1, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data("API error\n".utf8))
        }

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func timeoutIsUnavailable() async throws {
        let runner = FakeRunner { _ in .timedOut }

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func runnerThatCannotStartClaudeIsUnavailable() async throws {
        let runner = FakeRunner { _ in throw CocoaError(.executableNotLoadable) }

        #expect(await provider(runner).fetch() == .unavailable)
    }

    /// Interim until the `auth status` step exists.
    @Test func outputWithoutAUsageReportIsUnavailableForNow() async throws {
        let runner = FakeRunner { _ in
            .exited(status: 0, stdout: try Fixtures.data("usage-logged-out.stream.jsonl"), stderr: Data())
        }

        #expect(await provider(runner).fetch() == .unavailable)
        #expect(runner.commands.count == 1)
    }
}

/// Answers `claude --version` with the version fixture and passes every
/// other command on to `next`.
private nonisolated struct CurrentVersionRunner: CommandRunner {
    let next: FakeRunner

    func run(_ command: Command) async throws -> CommandResult {
        guard command.arguments == ["--version"] else { return try await next.run(command) }
        return .exited(status: 0, stdout: try Fixtures.data("version.txt"), stderr: Data())
    }
}
