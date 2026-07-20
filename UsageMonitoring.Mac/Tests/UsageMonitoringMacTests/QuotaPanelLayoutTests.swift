import CoreGraphics
import XCTest
@testable import UsageMonitoringMac

final class QuotaPanelLayoutTests: XCTestCase {
    func testOneTwoAndThreeCardHeights() {
        XCTAssertEqual(QuotaPanelLayout.windowSize(cardCount: 1).height, 95)
        XCTAssertEqual(QuotaPanelLayout.windowSize(cardCount: 2).height, 190)
        XCTAssertEqual(QuotaPanelLayout.windowSize(cardCount: 3).height, 285)
    }

    func testResizePreservesNearestTopEdgeAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let oldFrame = CGRect(x: 1200, y: 700, width: 216, height: 190)
        let resized = QuotaPanelLayout.resizedFrame(
            from: oldFrame,
            to: QuotaPanelLayout.windowSize(cardCount: 3),
            visibleFrame: screen)

        XCTAssertEqual(resized.maxY, oldFrame.maxY)
        XCTAssertGreaterThanOrEqual(resized.minX, screen.minX)
        XCTAssertLessThanOrEqual(resized.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(resized.minY, screen.minY)
        XCTAssertLessThanOrEqual(resized.maxY, screen.maxY)
    }

    func testResizePreservesNearestBottomEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let oldFrame = CGRect(x: 20, y: 10, width: 216, height: 95)
        let resized = QuotaPanelLayout.resizedFrame(
            from: oldFrame,
            to: QuotaPanelLayout.windowSize(cardCount: 2),
            visibleFrame: screen)

        XCTAssertEqual(resized.minY, oldFrame.minY)
    }
}
