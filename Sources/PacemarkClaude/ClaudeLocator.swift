import Foundation

/// Finds the `claude` binary: first in its known install locations, then
/// by asking the user's login shell.
nonisolated struct ClaudeLocator: Sendable {
    let homeDirectory: URL
    /// Prefix for the absolute locations; `/` except in tests.
    let rootDirectory: URL
    let userName: String
    let loginShell: URL
    /// Runs the login shell.
    let runner: any CommandRunner

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rootDirectory: URL = URL(filePath: "/", directoryHint: .isDirectory),
        userName: String = NSUserName(),
        loginShell: URL = ClaudeLocator.userLoginShell(),
        runner: any CommandRunner
    ) {
        self.homeDirectory = homeDirectory
        self.rootDirectory = rootDirectory
        self.userName = userName
        self.loginShell = loginShell
        self.runner = runner
    }

    /// The first known location that holds an executable file, else what
    /// the login shell finds; nil when neither finds one.
    func locate() async -> URL? {
        if let claude = knownLocations().first(where: Self.isExecutableFile) {
            claudeLog.info("Found claude at \(claude.path(percentEncoded: false), privacy: .public) in a known location")
            return claude
        }
        if let claude = await askLoginShell() {
            claudeLog.info(
                "Found claude at \(claude.path(percentEncoded: false), privacy: .public) through the login shell \(loginShell.path(percentEncoded: false), privacy: .public)"
            )
            return claude
        }
        claudeLog.error("Found no claude in the known locations or through the login shell")
        return nil
    }

    private func knownLocations() -> [URL] {
        [
            homeDirectory.appending(path: ".local/bin/claude"),
            rootDirectory.appending(path: "opt/homebrew/bin/claude"),
            rootDirectory.appending(path: "usr/local/bin/claude"),
            homeDirectory.appending(path: ".local/share/mise/shims/claude"),
            homeDirectory.appending(path: ".asdf/shims/claude"),
        ]
            + nvmLocations()
            + [homeDirectory.appending(path: ".claude/local/claude")]
    }

    /// `~/.nvm/versions/node/*/bin/claude`, newest Node version first.
    private func nvmLocations() -> [URL] {
        let versions = homeDirectory.appending(path: ".nvm/versions/node", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: versions.path(percentEncoded: false))) ?? []
        return names
            .sorted { versionNumbers($0).lexicographicallyPrecedes(versionNumbers($1)) }
            .reversed()
            .map { versions.appending(path: $0).appending(path: "bin/claude") }
    }

    /// `v20.10.0` → `[20, 10, 0]`, so `v20.10.0` sorts above `v20.9.1`.
    private func versionNumbers(_ name: String) -> [Int] {
        name.drop(while: { $0 == "v" }).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// `<shell> -l -i -c 'command -v claude'`: the login shell sees the
    /// user's PATH, and `-i` activates tools like mise that only hook into
    /// interactive shells.
    private func askLoginShell() async -> URL? {
        let command = Command(
            executable: loginShell,
            arguments: ["-l", "-i", "-c", "command -v claude"],
            // What a terminal gets from launchd; the startup files add the rest.
            environment: [
                "HOME": homeDirectory.pathWithoutTrailingSlash,
                "USER": userName,
                "LOGNAME": userName,
                "SHELL": loginShell.path(percentEncoded: false),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            workingDirectory: homeDirectory,
            standardInput: URL(filePath: "/dev/null"),
            timeout: .seconds(5)
        )
        guard case .exited(_, let stdout, _)? = try? await runner.run(command) else { return nil }
        return String(decoding: stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { URL(filePath: $0.trimmingCharacters(in: .whitespaces)) }
            .last(where: Self.isExecutableFile)
    }

    /// An executable file after resolving symlinks: dead symlinks,
    /// directories and non-executable files don't count.
    static func isExecutableFile(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// The shell from the user record, not `$SHELL`, which GUI apps may lack.
    static func userLoginShell() -> URL {
        guard let user = getpwuid(getuid()), let shell = user.pointee.pw_shell, shell.pointee != 0 else {
            return URL(filePath: "/bin/zsh")
        }
        return URL(filePath: String(cString: shell))
    }
}

nonisolated extension URL {
    /// The path without a trailing slash, as a shell would set `HOME`.
    var pathWithoutTrailingSlash: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
