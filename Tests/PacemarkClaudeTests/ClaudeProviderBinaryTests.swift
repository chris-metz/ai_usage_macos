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
