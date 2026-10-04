import Foundation
import Testing

/// Real `claude` output and hand-edited variants, bundled as test resources.
nonisolated enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "missing fixture \(name)"
        )
        return try Data(contentsOf: url)
    }
}

/// Seconds since 1970, written as literals so expected dates don't come
/// from the parser's own date code.
func date(_ secondsSince1970: TimeInterval) -> Date {
    Date(timeIntervalSince1970: secondsSince1970)
}
