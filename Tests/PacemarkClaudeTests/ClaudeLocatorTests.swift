import Foundation
import Testing

@testable import PacemarkClaude

/// Runs on a temp home and a temp root, so the real `claude` on this Mac
/// never counts, and a fake runner answers for the login shell, so the
/// user's real shell never runs.
@Suite struct ClaudeLocatorTests {
    let directory: TemporaryDirectory
    let home: URL
    let root: URL
    /// The login shell knows no `claude`.
    let locator: ClaudeLocator

    init() throws {
        directory = try TemporaryDirectory()
        home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        locator = ClaudeLocator(
            homeDirectory: home, rootDirectory: root, userName: "tester", loginShell: fakeLoginShell,
            runner: FakeRunner { _ in .exited(status: 1, stdout: Data(), stderr: Data()) })
    }

    /// A locator whose login shell answers with `runner`.
    func locator(_ runner: FakeRunner) -> ClaudeLocator {
        ClaudeLocator(homeDirectory: home, rootDirectory: root, userName: "tester", loginShell: fakeLoginShell, runner: runner)
    }

    @Test func findsAnExecutableInAKnownLocation() async throws {
        let claude = home.appending(path: ".local/bin/claude")
        try makeExecutable(at: claude)

        #expect(await locator.locate() == claude)
    }

    @Test func knownLocationsWinInTheirOrder() async throws {
        let order = [
            home.appending(path: ".local/bin/claude"),
            root.appending(path: "opt/homebrew/bin/claude"),
            root.appending(path: "usr/local/bin/claude"),
            home.appending(path: ".local/share/mise/shims/claude"),
            home.appending(path: ".asdf/shims/claude"),
            home.appending(path: ".nvm/versions/node/v22.11.0/bin/claude"),
            home.appending(path: ".claude/local/claude"),
        ]
        for location in order { try makeExecutable(at: location) }

        for location in order {
            #expect(await locator.locate() == location)
            try FileManager.default.removeItem(at: location)
        }
        #expect(await locator.locate() == nil)
    }

    @Test func symlinkToAnExecutableCountsAndKeepsItsPath() async throws {
        let target = home.appending(path: ".local/share/claude/versions/2.1.289")
        let claude = home.appending(path: ".local/bin/claude")
        try makeExecutable(at: target)
        try makeSymlink(at: claude, to: target)

        #expect(await locator.locate() == claude)
    }

    @Test func deadSymlinkIsSkipped() async throws {
        try makeSymlink(at: home.appending(path: ".local/bin/claude"), to: home.appending(path: "gone/claude"))
        let fallback = root.appending(path: "opt/homebrew/bin/claude")
        try makeExecutable(at: fallback)

        #expect(await locator.locate() == fallback)
    }

    @Test func nonExecutableFileIsSkipped() async throws {
        try makeFile(at: home.appending(path: ".local/bin/claude"))
        let target = home.appending(path: "plain-file")
        try makeFile(at: target)
        try makeSymlink(at: root.appending(path: "opt/homebrew/bin/claude"), to: target)
        let fallback = root.appending(path: "usr/local/bin/claude")
        try makeExecutable(at: fallback)

        #expect(await locator.locate() == fallback)
    }

    @Test func directoryIsSkipped() async throws {
        try FileManager.default.createDirectory(
            at: home.appending(path: ".local/bin/claude"), withIntermediateDirectories: true)
        let fallback = root.appending(path: "opt/homebrew/bin/claude")
        try makeExecutable(at: fallback)

        #expect(await locator.locate() == fallback)
    }

    @Test func newestNvmNodeVersionWinsByNumericOrder() async throws {
        let nodeVersions = home.appending(path: ".nvm/versions/node")
        let newestFirst = ["v20.10.0", "v20.9.1", "v18.17.0", "v9.11.2"]
        for version in ["v9.11.2", "v20.9.1", "v18.17.0", "v20.10.0"] {
            try makeExecutable(at: nodeVersions.appending(path: "\(version)/bin/claude"))
        }
        // A newer Node without Claude Code doesn't count.
        try FileManager.default.createDirectory(
            at: nodeVersions.appending(path: "v22.0.0/bin"), withIntermediateDirectories: true)

        for version in newestFirst {
            let claude = nodeVersions.appending(path: "\(version)/bin/claude")
            #expect(await locator.locate() == claude)
            try FileManager.default.removeItem(at: claude)
        }
    }

    @Test func loginShellFindsClaudeOutsideTheKnownLocations() async throws {
        let claude = home.appending(path: ".volta/bin/claude")
        try makeExecutable(at: claude)
        let runner = FakeRunner { _ in .exited(status: 0, stdout: Data("\(claude.path)\n".utf8), stderr: Data()) }

        #expect(await locator(runner).locate() == claude)
    }

    /// Shell startup files may print anything before the answer.
    @Test func loginShellAnswerIsTheLastLineThatIsAnExecutablePath() async throws {
        let claude = home.appending(path: ".volta/bin/claude")
        try makeExecutable(at: claude)
        let stdout = """
            Last login: Sat Oct  3 09:12:44 on ttys001
            mise WARN  missing: node@22.11.0
            \(home.path)
            \(claude.path)  \n
            """
        let runner = FakeRunner { _ in .exited(status: 0, stdout: Data(stdout.utf8), stderr: Data("zsh: no job control\n".utf8)) }

        #expect(await locator(runner).locate() == claude)
    }

    @Test(arguments: [
        CommandResult.exited(status: 1, stdout: Data(), stderr: Data()),
        .exited(status: 0, stdout: Data("claude: aliased to ~/.claude/local/claude\n".utf8), stderr: Data()),
        .exited(status: 0, stdout: Data("/nonexistent/bin/claude\n".utf8), stderr: Data()),
        .timedOut,
    ])
    func loginShellThatFindsNothingGivesNothing(answer: CommandResult) async throws {
        #expect(await locator(FakeRunner { _ in answer }).locate() == nil)
    }

    /// A relative line would resolve against Pacemark's own working
    /// directory, not the shell's.
    @Test func loginShellLineThatIsNoAbsolutePathDoesNotCount() async throws {
        // Enough `..` to reach `/` from any working directory, so the line
        // names /bin/sh, an executable file.
        let relative = String(repeating: "../", count: 64) + "bin/sh"
        let runner = FakeRunner { _ in .exited(status: 0, stdout: Data("\(relative)\n".utf8), stderr: Data()) }

        #expect(await locator(runner).locate() == nil)
    }

    @Test func loginShellThatCannotStartGivesNothing() async throws {
        #expect(await locator(FakeRunner { _ in throw CocoaError(.executableNotLoadable) }).locate() == nil)
    }

    @Test func asksTheLoginShellInteractivelyWithA5SecondTimeout() async throws {
        let runner = FakeRunner { _ in .exited(status: 1, stdout: Data(), stderr: Data()) }

        _ = await locator(runner).locate()

        let command = try #require(runner.commands.first)
        #expect(runner.commands.count == 1)
        #expect(command.executable == fakeLoginShell)
        #expect(command.arguments == ["-l", "-i", "-c", "command -v claude"])
        #expect(command.environment == [
            "HOME": directory.path + "/home",
            "USER": "tester",
            "LOGNAME": "tester",
            "SHELL": "/nonexistent/login-shell",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ])
        #expect(command.workingDirectory.standardizedFileURL == home.standardizedFileURL)
        #expect(command.standardInput.path(percentEncoded: false) == "/dev/null")
        #expect(command.timeout == .seconds(5))
    }

    @Test func knownLocationSkipsTheLoginShell() async throws {
        let claude = root.appending(path: "usr/local/bin/claude")
        try makeExecutable(at: claude)
        let runner = FakeRunner { _ in .exited(status: 1, stdout: Data(), stderr: Data()) }

        #expect(await locator(runner).locate() == claude)
        #expect(runner.commands.isEmpty)
    }
}
