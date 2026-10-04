import Foundation

/// A fresh, empty directory that is removed when the value goes away.
final class TemporaryDirectory {
    /// The absolute path, without a trailing slash.
    let path: String
    let url: URL

    init() throws {
        path = FileManager.default.temporaryDirectory.path(percentEncoded: false)
            .trimmingSuffix("/") + "/PacemarkClaudeTests-\(UUID().uuidString)"
        url = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
