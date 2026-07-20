import Foundation
import XCTest
@testable import UsageMonitoringMac

final class CodexExecutableLocatorMacTests: XCTestCase {
    func testStandardCandidatesIncludeCurrentDesktopAndPluginAppServerExecutables() {
        let codexHome = URL(fileURLWithPath: "/tmp/test-codex-home", isDirectory: true)
        let homeDirectory = URL(fileURLWithPath: "/tmp/test-home", isDirectory: true)

        let candidates = CodexExecutableLocatorMac.standardCandidatePaths(
            codexHome: codexHome,
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(candidates.first, "/Applications/ChatGPT.app/Contents/Resources/codex")
        XCTAssertTrue(candidates.contains("/tmp/test-codex-home/plugins/.plugin-appserver/codex"))
    }
}
