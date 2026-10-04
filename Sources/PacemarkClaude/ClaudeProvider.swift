import Foundation
import PacemarkKit

/// Reads the Claude limits through the installed Claude Code: locate the
/// binary, run `/usage` isolated, parse its `usage_report` (ADR 0001).
public nonisolated final class ClaudeProvider: Provider {
    public let id = "claude"
    public let name = "Claude"

    private let homeDirectory: URL
    private let userName: String
    private let locator: ClaudeLocator
    private let runner: any CommandRunner

    public convenience init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(homeDirectory: home, userName: NSUserName(), locator: ClaudeLocator(homeDirectory: home), runner: ProcessRunner())
    }

    init(homeDirectory: URL, userName: String, locator: ClaudeLocator, runner: any CommandRunner) {
        self.homeDirectory = homeDirectory
        self.userName = userName
        self.locator = locator
        self.runner = runner
    }

    @concurrent
    public func fetch() async -> FetchResult {
        // Interim: "not found" gives `unavailable` until it exists.
        guard let claude = locator.locate() else {
            claudeLog.error("Found no claude in the known locations")
            return .unavailable
        }
        claudeLog.info("Found claude at \(claude.path(percentEncoded: false), privacy: .public) in a known location")

        guard case .exited(0, let stdout, _)? = await run(usageCommand(claude)) else { return .unavailable }
        switch ClaudeParser.usageReport(from: stdout) {
        case .limits(let limits):
            return .limits(limits)
        case .rateLimitsNull:
            claudeLog.error("The usage report has rate_limits: null")
            return .unavailable
        case .missing:
            claudeLog.error("The /usage output has no usage report")
            return await loginResult(claude)
        case .unexpected(let reason):
            claudeLog.error("The usage report breaks the schema: \(reason, privacy: .public)")
            return .problem(.unexpectedResponse)
        }
    }

    /// Asks `claude auth status` why `/usage` gave no report. Only its JSON
    /// counts: the exit status is 1 when logged out.
    private func loginResult(_ claude: URL) async -> FetchResult {
        guard case .exited(_, let stdout, _)? = await run(isolated(claude, arguments: ["auth", "status"])) else {
            return .unavailable
        }
        switch ClaudeParser.authStatus(from: stdout) {
        case .loggedOut?:
            claudeLog.error("claude auth status says logged out")
            return .problem(.notLoggedIn)
        case .loggedIn?:
            claudeLog.error("claude auth status says logged in, yet /usage gave no usage report")
            return .problem(.unexpectedResponse)
        case nil:
            claudeLog.error("claude auth status gave no readable loggedIn")
            return .unavailable
        }
    }

    /// Runs one invocation and logs its exit status, duration and stderr;
    /// nil when it couldn't start.
    private func run(_ command: Command) async -> CommandResult? {
        let name = command.arguments.last ?? ""
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try FileManager.default.createDirectory(at: command.workingDirectory, withIntermediateDirectories: true)
            let result = try await runner.run(command)
            let duration = clock.now - start
            switch result {
            case .exited(let status, _, let stderr):
                let stderrText = String(decoding: stderr.prefix(2048), as: UTF8.self)
                claudeLog.log(
                    "claude \(name, privacy: .public) exited with status \(status) after \(duration, privacy: .public); stderr: \(stderrText, privacy: .public)"
                )
            case .timedOut:
                claudeLog.error("claude \(name, privacy: .public) timed out after \(duration, privacy: .public)")
            }
            return result
        } catch {
            claudeLog.error("claude \(name, privacy: .public) could not start: \(error, privacy: .public)")
            return nil
        }
    }

    /// `claude -p … "/usage"`, isolated from the user's settings, hooks and
    /// MCP servers.
    private func usageCommand(_ claude: URL) -> Command {
        isolated(claude, arguments: [
            "-p", "--no-session-persistence", "--strict-mcp-config", "--safe-mode", "--setting-sources", "",
            "--output-format", "stream-json", "--verbose", "/usage",
        ])
    }

    /// The environment, working directory, stdin and timeout every
    /// invocation of `claude` shares.
    private func isolated(_ claude: URL, arguments: [String]) -> Command {
        Command(
            executable: claude,
            arguments: arguments,
            // Never CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it turns rate_limits into null.
            environment: [
                "HOME": homePath,
                "USER": userName,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "DISABLE_AUTOUPDATER": "1",
                "DISABLE_TELEMETRY": "1",
            ],
            workingDirectory: workingDirectory,
            standardInput: URL(filePath: "/dev/null"),
            timeout: .seconds(30)
        )
    }

    /// The home path without a trailing slash, as a shell would set `HOME`.
    private var homePath: String {
        let path = homeDirectory.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The same empty folder every time, so Claude Code only ever sees one.
    private var workingDirectory: URL {
        homeDirectory.appending(path: "Library/Caches/xyz.chrismetz.pacemark/claude-cwd", directoryHint: .isDirectory)
    }
}
