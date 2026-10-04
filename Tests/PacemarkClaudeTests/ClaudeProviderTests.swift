import Foundation
import PacemarkKit
import Testing

@testable import PacemarkClaude

/// The problems as the spec's appendix words them.
private let notLoggedIn = Problem(
    heading: "Claude Code is not logged in",
    message: "Run `claude` in Terminal and log in.",
    link: nil
)
private let unexpectedResponse = Problem(
    heading: "Can't read your limits",
    message: "Claude changed how it reports limits. A newer version of Pacemark should fix this.",
    link: ProblemLink(title: "Open on GitHub", url: URL(string: "https://github.com/chris-metz/pacemark")!)
)

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

    func provider(_ runner: FakeRunner) -> ClaudeProvider {
        ClaudeProvider(
            homeDirectory: home,
            userName: "tester",
            locator: ClaudeLocator(homeDirectory: home, rootDirectory: directory.url.appending(path: "root")),
            runner: runner
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

    @Test func nullRateLimitsAreUnavailable() async throws {
        let runner = FakeRunner.claude(usage: try .fixture("variant-rate-limits-null.stream.jsonl"))

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func schemaMismatchIsTheUnexpectedResponseProblem() async throws {
        let runner = FakeRunner.claude(usage: try .fixture("variant-wrong-type.stream.jsonl"))

        #expect(await provider(runner).fetch() == .problem(unexpectedResponse))
    }

    @Test func nonZeroExitIsUnavailableEvenWithLimitsOnStdout() async throws {
        let runner = FakeRunner.claude(
            usage: .exited(status: 1, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data("API error\n".utf8))
        )

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func timeoutIsUnavailable() async throws {
        let runner = FakeRunner.claude(usage: .timedOut)

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func runnerThatCannotStartClaudeIsUnavailable() async throws {
        let runner = FakeRunner { _ in throw CocoaError(.executableNotLoadable) }

        #expect(await provider(runner).fetch() == .unavailable)
    }

    /// Interim until the "Claude Code not found" problem exists.
    @Test func missingClaudeIsUnavailableForNow() async throws {
        try FileManager.default.removeItem(at: claude)
        let runner = FakeRunner { _ in .exited(status: 0, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data()) }

        #expect(await provider(runner).fetch() == .unavailable)
        #expect(runner.commands.isEmpty)
    }

    /// `auth status` exits with 1 when logged out; only its JSON counts.
    @Test func noReportWhileLoggedOutIsTheNotLoggedInProblem() async throws {
        let runner = FakeRunner.claude(
            usage: try .fixture("usage-logged-out.stream.jsonl"),
            authStatus: try .fixture("auth-status-logged-out.json", status: 1)
        )

        #expect(await provider(runner).fetch() == .problem(notLoggedIn))
    }

    @Test func noReportWhileLoggedInIsTheUnexpectedResponseProblem() async throws {
        let runner = FakeRunner.claude(
            usage: try .fixture("usage-logged-out.stream.jsonl"),
            authStatus: try .fixture("auth-status-logged-in.json")
        )

        #expect(await provider(runner).fetch() == .problem(unexpectedResponse))
    }

    @Test(arguments: [
        CommandResult.timedOut,
        .exited(status: 1, stdout: Data(), stderr: Data("error: unknown command 'auth'\n".utf8)),
        .exited(status: 0, stdout: Data("Logged in as someone\n".utf8), stderr: Data()),
    ])
    func unreadableAuthStatusIsUnavailable(authStatus: CommandResult) async throws {
        let runner = FakeRunner.claude(usage: try .fixture("usage-logged-out.stream.jsonl"), authStatus: authStatus)

        #expect(await provider(runner).fetch() == .unavailable)
    }

    @Test func authStatusRunsWithTheSameIsolationAsUsage() async throws {
        let runner = FakeRunner.claude(
            usage: try .fixture("usage-logged-out.stream.jsonl"),
            authStatus: try .fixture("auth-status-logged-out.json", status: 1)
        )

        _ = await provider(runner).fetch()

        let usage = try #require(runner.commands.first { $0.arguments.last == "/usage" })
        var expected = usage
        expected.arguments = ["auth", "status"]
        #expect(runner.commands(["auth", "status"]) == [expected])
    }

    @Test(arguments: [
        "usage.stream.jsonl", "variant-rate-limits-null.stream.jsonl", "variant-wrong-type.stream.jsonl",
    ])
    func authStatusNeverRunsWhenThereIsAReport(usage: String) async throws {
        let runner = FakeRunner.claude(
            usage: try .fixture(usage),
            authStatus: try .fixture("auth-status-logged-out.json", status: 1)
        )

        _ = await provider(runner).fetch()

        #expect(runner.commands(["auth", "status"]).isEmpty)
    }
}
