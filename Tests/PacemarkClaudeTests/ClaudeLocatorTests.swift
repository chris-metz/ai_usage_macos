import Foundation
import Testing

@testable import PacemarkClaude

/// Runs on a temp home and a temp root, so the real `claude` on this Mac
/// never counts.
@Suite struct ClaudeLocatorTests {
    let directory: TemporaryDirectory
    let home: URL
    let root: URL
    let locator: ClaudeLocator

    init() throws {
        directory = try TemporaryDirectory()
        home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        locator = ClaudeLocator(homeDirectory: home, rootDirectory: root)
    }

    @Test func findsAnExecutableInAKnownLocation() throws {
        let claude = home.appending(path: ".local/bin/claude")
        try makeExecutable(at: claude)

        #expect(locator.locate() == claude)
    }

    @Test func knownLocationsWinInTheirOrder() throws {
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
            #expect(locator.locate() == location)
            try FileManager.default.removeItem(at: location)
        }
        #expect(locator.locate() == nil)
    }

    @Test func symlinkToAnExecutableCountsAndKeepsItsPath() throws {
        let target = home.appending(path: ".local/share/claude/versions/2.1.289")
        let claude = home.appending(path: ".local/bin/claude")
        try makeExecutable(at: target)
        try makeSymlink(at: claude, to: target)

        #expect(locator.locate() == claude)
    }

    @Test func deadSymlinkIsSkipped() throws {
        try makeSymlink(at: home.appending(path: ".local/bin/claude"), to: home.appending(path: "gone/claude"))
        let fallback = root.appending(path: "opt/homebrew/bin/claude")
        try makeExecutable(at: fallback)

        #expect(locator.locate() == fallback)
    }

    @Test func nonExecutableFileIsSkipped() throws {
        try makeFile(at: home.appending(path: ".local/bin/claude"))
        let target = home.appending(path: "plain-file")
        try makeFile(at: target)
        try makeSymlink(at: root.appending(path: "opt/homebrew/bin/claude"), to: target)
        let fallback = root.appending(path: "usr/local/bin/claude")
        try makeExecutable(at: fallback)

        #expect(locator.locate() == fallback)
    }

    @Test func directoryIsSkipped() throws {
        try FileManager.default.createDirectory(
            at: home.appending(path: ".local/bin/claude"), withIntermediateDirectories: true)
        let fallback = root.appending(path: "opt/homebrew/bin/claude")
        try makeExecutable(at: fallback)

        #expect(locator.locate() == fallback)
    }

    @Test func newestNvmNodeVersionWinsByNumericOrder() throws {
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
            #expect(locator.locate() == claude)
            try FileManager.default.removeItem(at: claude)
        }
    }
}

private func makeExecutable(at url: URL) throws {
    try makeFile(at: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
}

private func makeSymlink(at url: URL, to target: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
}

private func makeFile(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
}
