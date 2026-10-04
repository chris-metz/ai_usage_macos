import Foundation
import Testing

@testable import PacemarkClaude

@Suite struct AuthStatusParserTests {
    @Test func loggedInFixtureIsLoggedIn() throws {
        let status = ClaudeParser.authStatus(from: try Fixtures.data("auth-status-logged-in.json"))

        #expect(status == .loggedIn)
    }

    @Test func loggedOutFixtureIsLoggedOut() throws {
        let status = ClaudeParser.authStatus(from: try Fixtures.data("auth-status-logged-out.json"))

        #expect(status == .loggedOut)
    }

    @Test(arguments: [
        "",
        "Not logged in. Run claude to log in.\n",
        #"{"authMethod":"none"}"#,
        #"{"loggedIn":"false"}"#,
        #"{"loggedIn":null}"#,
        #"[{"loggedIn":false}]"#,
    ])
    func anythingButALoggedInFlagIsUnreadable(stdout: String) {
        #expect(ClaudeParser.authStatus(from: Data(stdout.utf8)) == nil)
    }
}
