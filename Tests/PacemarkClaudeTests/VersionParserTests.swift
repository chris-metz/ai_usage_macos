import Foundation
import Testing

@testable import PacemarkClaude

@Suite struct VersionParserTests {
    @Test func versionFixtureGivesItsLeadingVersionNumber() throws {
        let version = try #require(ClaudeParser.version(from: try Fixtures.data("version.txt")))

        #expect(version.text == "2.1.289")
        #expect(!version.isTooOld)
    }

    @Test(arguments: [
        ("2.1.282 (Claude Code)", true),
        ("2.1.283 (Claude Code)", false),
        ("2.1.284 (Claude Code)", false),
        ("2.0.999 (Claude Code)", true),
        ("2.2.0 (Claude Code)", false),
        ("1.9.300", true),
        ("10.0.0", false),
        // Missing components count as 0.
        ("2.1", true),
        ("3", false),
        ("2.1.283.0", false),
        ("2.1.283.1", false),
    ])
    func versionIsTooOldBelow2_1_283(output: String, isTooOld: Bool) throws {
        let version = try #require(ClaudeParser.version(from: Data(output.utf8)))

        #expect(version.isTooOld == isTooOld)
    }

    @Test(arguments: [
        "",
        "Claude Code 2.1.289",
        "v2.1.289",
        "(Claude Code)\n",
        "99999999999999999999.1.0",
    ])
    func outputWithoutALeadingVersionNumberIsUnparseable(output: String) {
        #expect(ClaudeParser.version(from: Data(output.utf8)) == nil)
    }
}
