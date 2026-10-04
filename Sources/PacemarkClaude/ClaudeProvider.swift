import Foundation
import PacemarkKit
import Synchronization

/// Reads the Claude limits through the installed Claude Code: locate the
/// binary, check its version, run `/usage` isolated, parse its
/// `usage_report` (ADR 0001).
public nonisolated final class ClaudeProvider: Provider {
    public let id = "claude"
    public let name = "Claude"

    private let homeDirectory: URL
    private let userName: String
    private let locator: ClaudeLocator
    private let runner: any CommandRunner
    /// The found binary and its version check, kept between queries;
    /// never limit values.
    private let binaryCache = Mutex(BinaryCache())

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
        guard let claude = await locate() else { return .problem(.claudeCodeNotFound) }
        if let settled = await checkVersion(of: claude) { return settled }

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

    /// Runs one invocation in its working directory, created if missing,
    /// and logs it; nil when it couldn't start.
    private func run(_ command: Command) async -> CommandResult? {
        do {
            try FileManager.default.createDirectory(at: command.workingDirectory, withIntermediateDirectories: true)
        } catch {
            claudeLog.error("Could not create the working directory for claude: \(error, privacy: .public)")
            return nil
        }
        return await runner.runLogged(command)
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
        var environment = Command.baseEnvironment(homeDirectory: homeDirectory, userName: userName)
        environment["DISABLE_AUTOUPDATER"] = "1"
        environment["DISABLE_TELEMETRY"] = "1"
        // Never CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it turns rate_limits into null.
        return Command(
            executable: claude,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            standardInput: Command.noInput,
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
    /// The found binary and its version check, kept between queries.
    /// `fetch()` never runs concurrently, so reading it, awaiting, then
    /// writing it is safe.
    fileprivate struct BinaryCache {
        /// The binary found last; searched again once it isn't executable.
        var claude: URL?
        /// The last version check that ran to the end, and which binary it
        /// checked.
        var versionCheck: (binary: BinaryIdentity, result: FetchResult?)?
    }

    /// Which file a path runs: `claude update` re-points the native
    /// installer's symlink, Homebrew and mise change its target, and npm
    /// changes the file's modification date.
    fileprivate struct BinaryIdentity: Equatable {
        /// Symlinks resolved.
        let path: String
        let modificationDate: Date?

        init(of url: URL) {
            let path = url.path(percentEncoded: false)
            if let resolved = realpath(path, nil) {
                self.path = String(cString: resolved)
                free(resolved)
            } else {
                self.path = path
            }
            modificationDate = (try? FileManager.default.attributesOfItem(atPath: self.path))?[.modificationDate] as? Date
        }
    }

    /// The remembered binary while it's still executable, else the result of
    /// a new search. While nothing is found, every query searches again, so
    /// a fresh install is picked up.
    private func locate() async -> URL? {
        if let claude = binaryCache.withLock(\.claude), ClaudeLocator.isExecutableFile(claude) {
            return claude
        }
        let claude = await locator.locate()
        binaryCache.withLock { $0.claude = claude }
        return claude
    }

    /// The result that ends the query when `claude` is too old or the check
    /// fails; nil to carry on. A check that ran to the end counts until the
    /// binary's identity changes; a failed one runs again on the next query.
    private func checkVersion(of claude: URL) async -> FetchResult? {
        let binary = BinaryIdentity(of: claude)
        if let check = binaryCache.withLock(\.versionCheck), check.binary == binary { return check.result }
        let result = await runVersionCheck(of: claude)
        if result != .unavailable { binaryCache.withLock { $0.versionCheck = (binary, result) } }
        return result
    }

    private func runVersionCheck(of claude: URL) async -> FetchResult? {
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
