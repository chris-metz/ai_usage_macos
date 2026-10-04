import Foundation
import PacemarkKit
import Synchronization
import Testing

@testable import PacemarkClaude

/// Steps 1 and 2 of a query, locating `claude` and checking its version,
/// on a temp home and root. The fake `claude` files are never run: a
/// `FakeRunner` answers `--version` with the file's contents, so a file
/// holding `2.1.282 (Claude Code)` is that version.
@Suite struct ClaudeProviderBinaryTests {
    let directory: TemporaryDirectory
    let home: URL
    let root: URL

    init() throws {
        directory = try TemporaryDirectory()
        home = URL(filePath: directory.path + "/home", directoryHint: .isDirectory)
        root = URL(filePath: directory.path + "/root", directoryHint: .isDirectory)
    }

    /// A provider whose locator and invocations both go to `runner`.
    func provider(_ runner: FakeRunner) -> ClaudeProvider {
        ClaudeProvider(
            homeDirectory: home,
            userName: "tester",
            locator: ClaudeLocator(
                homeDirectory: home, rootDirectory: root, userName: "tester", loginShell: loginShell, runner: runner),
            runner: runner
        )
    }

    @Test func nothingFoundIsTheNotFoundProblem() async throws {
        let runner = fakeRunner()

        let result = await provider(runner).fetch()

        #expect(result == .problem(Problem(
            heading: "Claude Code not found",
            message: "Pacemark reads your limits through Claude Code. Install it and log in.",
            link: ProblemLink(title: "Install Claude Code", url: try #require(URL(string: "https://code.claude.com/docs/en/setup")))
        )))
        #expect(runner.commands.map(\.executable) == [loginShell])
    }

    @Test func freshInstallIsPickedUpOnTheNextQuery() async throws {
        let runner = fakeRunner()
        let provider = provider(runner)
        #expect(await provider.fetch() == .problem(.claudeCodeNotFound))

        try installClaude("2.1.289", at: home.appending(path: ".local/bin/claude"))

        #expect(await provider.fetch().isLimits)
    }

    @Test func foundPathIsRememberedWhileItIsExecutable() async throws {
        let homebrew = root.appending(path: "opt/homebrew/bin/claude")
        try installClaude("2.1.289", at: homebrew)
        let runner = fakeRunner()
        let provider = provider(runner)
        _ = await provider.fetch()

        // A location that comes first in the search doesn't matter now.
        try installClaude("2.1.289", at: home.appending(path: ".local/bin/claude"))
        _ = await provider.fetch()

        #expect(usageRuns(runner) == [homebrew, homebrew])
    }

    @Test func rememberedPathThatDisappearsTriggersANewSearch() async throws {
        let homebrew = root.appending(path: "opt/homebrew/bin/claude")
        let nativeInstall = home.appending(path: ".local/bin/claude")
        try installClaude("2.1.289", at: homebrew)
        let runner = fakeRunner()
        let provider = provider(runner)
        _ = await provider.fetch()
        try installClaude("2.1.289", at: nativeInstall)

        try FileManager.default.removeItem(at: homebrew)
        _ = await provider.fetch()

        #expect(usageRuns(runner) == [homebrew, nativeInstall])
    }

    @Test func pathFromTheLoginShellIsRemembered() async throws {
        let volta = home.appending(path: ".volta/bin/claude")
        try installClaude("2.1.289", at: volta)
        let runner = fakeRunner(loginShell: "\(volta.path)\n")
        let provider = provider(runner)

        _ = await provider.fetch()
        _ = await provider.fetch()

        #expect(usageRuns(runner) == [volta, volta])
        #expect(runner.commands.filter { $0.executable == loginShell }.count == 1)
    }

    @Test func versionBelow2_1_283IsTheTooOldProblemWithTheFoundVersion() async throws {
        try installClaude("2.1.282", at: home.appending(path: ".local/bin/claude"))
        let runner = fakeRunner()

        let result = await provider(runner).fetch()

        #expect(result == .problem(Problem(
            heading: "Claude Code is too old",
            message: "Pacemark needs version 2.1.283 or later (found 2.1.282). Run `claude update` in Terminal.",
            link: nil
        )))
        #expect(usageRuns(runner).isEmpty)
    }

    @Test(arguments: [
        CommandResult.exited(status: 1, stdout: Data("2.1.289 (Claude Code)\n".utf8), stderr: Data("error\n".utf8)),
        .timedOut,
    ])
    func failedVersionCheckIsUnavailable(answer: CommandResult) async throws {
        try installClaude("2.1.289", at: home.appending(path: ".local/bin/claude"))
        let runner = fakeRunner(version: { _ in answer })

        #expect(await provider(runner).fetch() == .unavailable)
        #expect(usageRuns(runner).isEmpty)
    }

    @Test func versionCheckThatCannotStartIsUnavailable() async throws {
        try installClaude("2.1.289", at: home.appending(path: ".local/bin/claude"))
        let runner = fakeRunner(version: { _ in throw CocoaError(.executableNotLoadable) })

        #expect(await provider(runner).fetch() == .unavailable)
        #expect(usageRuns(runner).isEmpty)
    }

    /// A changed `--version` format must never block the app.
    @Test func unparseableVersionCarriesOn() async throws {
        try installClaude("2.1.289", at: home.appending(path: ".local/bin/claude"))
        let runner = fakeRunner(version: { _ in .exited(status: 0, stdout: Data("Claude Code (dev build)\n".utf8), stderr: Data()) })

        #expect(await provider(runner).fetch().isLimits)
    }

    @Test func checksTheVersionWithTheIsolatedInvocation() async throws {
        let claude = home.appending(path: ".local/bin/claude")
        try installClaude("2.1.289", at: claude)
        let runner = fakeRunner()

        _ = await provider(runner).fetch()

        let command = try #require(runner.commands.first)
        #expect(command.executable == claude)
        #expect(command.arguments == ["--version"])
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
}

/// The binaries `/usage` ran with, in order.
private func usageRuns(_ runner: FakeRunner) -> [URL] {
    runner.commands.filter { $0.arguments.last == "/usage" }.map(\.executable)
}

extension FetchResult {
    fileprivate var isLimits: Bool {
        if case .limits = self { true } else { false }
    }
}

/// Never run: a fake runner answers in its place.
private let loginShell = URL(filePath: "/nonexistent/login-shell")

/// Answers like a Mac with the fake binaries on disk: `--version` with the
/// binary's contents, the login shell with `loginShell`'s stdout, and
/// `/usage` with the usage fixture.
private func fakeRunner(
    loginShell shellStdout: String = "",
    version: (@Sendable (Command) throws -> CommandResult)? = nil
) -> FakeRunner {
    FakeRunner { command in
        switch command.arguments {
        case ["--version"]:
            if let version { return try version(command) }
            return .exited(status: 0, stdout: try Data(contentsOf: command.executable), stderr: Data())
        case ["-l", "-i", "-c", "command -v claude"]:
            return .exited(status: shellStdout.isEmpty ? 1 : 0, stdout: Data(shellStdout.utf8), stderr: Data())
        default:
            return .exited(status: 0, stdout: try Fixtures.data("usage.stream.jsonl"), stderr: Data())
        }
    }
}

/// A fake `claude` whose `--version` prints `version`.
private func installClaude(_ version: String, at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("\(version) (Claude Code)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
}
