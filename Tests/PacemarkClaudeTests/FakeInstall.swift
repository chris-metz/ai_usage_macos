import Foundation
import Testing

@testable import PacemarkClaude

/// Never run: a fake runner answers in its place.
let fakeLoginShell = URL(filePath: "/nonexistent/login-shell")

/// A provider on a temp home and root, so the real `claude` on this Mac
/// never counts. The locator's login shell and every invocation go to
/// `runner`.
func makeProvider(home: URL, root: URL, runner: any CommandRunner) -> ClaudeProvider {
    ClaudeProvider(
        homeDirectory: home,
        userName: "tester",
        locator: ClaudeLocator(
            homeDirectory: home, rootDirectory: root, userName: "tester", loginShell: fakeLoginShell, runner: runner),
        runner: runner
    )
}

/// A small shell script at `url`, its directories created.
func makeFile(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
}

func makeExecutable(at url: URL) throws {
    try makeFile(at: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
}

/// A symlink at `url` to `target`. With `modified`, the symlink's own
/// modification date, so re-creating it changes nothing but its target.
func makeSymlink(at url: URL, to target: URL, modified: Date? = nil) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    guard let modified else { return }
    let seconds = Int(modified.timeIntervalSince1970)
    var times = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
    #expect(lutimes(url.path(percentEncoded: false), &times) == 0)
}
