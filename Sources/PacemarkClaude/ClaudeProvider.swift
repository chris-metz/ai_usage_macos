import Foundation
import PacemarkKit
import Synchronization

/// Reads the Claude limits through the installed Claude Code: locate the
/// binary, run `/usage` isolated, parse its `usage_report` (ADR 0001).
public nonisolated final class ClaudeProvider: Provider {
    public let id = "claude"
    public let name = "Claude"

    private let homeDirectory: URL
    private let userName: String
    private let locator: ClaudeLocator
    private let runner: any CommandRunner
    /// What the provider remembers between queries; never limit values.
    private let memory = Mutex(Memory())

    public convenience init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = ProcessRunner()
        self.init(
            homeDirectory: home, userName: NSUserName(), locator: ClaudeLocator(homeDirectory: home, runner: runner),
            runner: runner)
    }

    init(homeDirectory: URL, userName: String, locator: ClaudeLocator, runner: any CommandRunner) {
        self.homeDirectory = homeDirectory
        self.userName = userName
        self.locator = locator
        self.runner = runner
    }

    @concurrent
    public func fetch() async -> FetchResult {
        // Interim: "rate_limits: null", the schema problems and the
        // `auth status` step all give `unavailable` until they exist.
        guard let claude = await locate() else { return .problem(.claudeCodeNotFound) }
        if let settled = await checkVersion(of: claude) { return settled }

        guard case .exited(0, let stdout, _)? = await run(usageCommand(claude)) else { return .unavailable }
        switch ClaudeParser.usageReport(from: stdout) {
        case .limits(let limits):
            return .limits(limits)
        case .rateLimitsNull:
            claudeLog.error("The usage report has rate_limits: null")
        case .missing:
            claudeLog.error("The /usage output has no usage report")
        case .unexpected(let reason):
            claudeLog.error("The usage report breaks the schema: \(reason, privacy: .public)")
        }
        return .unavailable
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
                "HOME": homeDirectory.pathWithoutTrailingSlash,
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

    /// The same empty folder every time, so Claude Code only ever sees one.
    private var workingDirectory: URL {
        homeDirectory.appending(path: "Library/Caches/xyz.chrismetz.pacemark/claude-cwd", directoryHint: .isDirectory)
    }
}

// MARK: - Steps 1 and 2: locate the binary and check its version

extension ClaudeProvider {
    /// What the provider remembers between queries. `fetch()` never runs
    /// concurrently, so reading it, awaiting, then writing it is safe.
    fileprivate struct Memory {
        /// The binary found last; searched again once it isn't executable.
        var claude: URL?
    }

    /// The remembered binary while it's still executable, else the result of
    /// a new search. While nothing is found, every query searches again, so
    /// a fresh install is picked up.
    private func locate() async -> URL? {
        if let claude = memory.withLock(\.claude), ClaudeLocator.isExecutableFile(claude) {
            return claude
        }
        let claude = await locator.locate()
        memory.withLock { $0.claude = claude }
        return claude
    }

    /// The result that ends the query when `claude` is too old or the check
    /// fails; nil to carry on.
    private func checkVersion(of claude: URL) async -> FetchResult? {
        guard case .exited(0, let stdout, _)? = await run(isolated(claude, arguments: ["--version"])) else {
            claudeLog.error("The version check failed")
            return .unavailable
        }
        guard let version = ClaudeParser.version(from: stdout) else {
            let output = String(decoding: stdout.prefix(2048), as: UTF8.self)
            claudeLog.error("Found no version number in \(output, privacy: .public); carrying on")
            return nil
        }
        if version.isTooOld {
            claudeLog.error(
                "claude \(version.text, privacy: .public) is older than \(ClaudeVersion.minimum.text, privacy: .public)")
            return .problem(.claudeCodeTooOld(found: version))
        }
        claudeLog.info("claude \(version.text, privacy: .public) is recent enough")
        return nil
    }
}
