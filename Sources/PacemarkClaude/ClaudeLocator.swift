import Foundation

/// Finds the `claude` binary in its known install locations.
nonisolated struct ClaudeLocator: Sendable {
    let homeDirectory: URL
    /// Prefix for the absolute locations; `/` except in tests.
    let rootDirectory: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rootDirectory: URL = URL(filePath: "/", directoryHint: .isDirectory)
    ) {
        self.homeDirectory = homeDirectory
        self.rootDirectory = rootDirectory
    }

    /// The first known location that holds an executable file.
    func locate() -> URL? {
        knownLocations().first(where: isExecutableFile)
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

    /// An executable file after resolving symlinks: dead symlinks,
    /// directories and non-executable files don't count.
    private func isExecutableFile(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }
}
