import AppKit
import XCTest
@testable import UsageMonitoringMac

final class WindowInteractionTests: XCTestCase {
    @MainActor
    func testDelegateCallbacksAreExposedToAppKit() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        XCTAssertTrue(delegate.responds(to: #selector(NSMenuDelegate.menuNeedsUpdate(_:))))
        XCTAssertTrue(delegate.responds(to: #selector(NSApplicationDelegate.applicationDidFinishLaunching(_:))))
        XCTAssertTrue(delegate.responds(to: #selector(NSApplicationDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:))))
        let controller = FloatingWindowController(preferences: AppPreferences())
        XCTAssertTrue(controller.responds(to: #selector(NSWindowDelegate.windowDidMove(_:))))
        XCTAssertTrue(controller.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
    }

    @MainActor
    func testDraggingMovesWindowAndClickThroughBlocksItUntilDisabled() throws {
        _ = NSApplication.shared
        let window = FloatingPanelWindow(
            contentRect: CGRect(x: 100, y: 100, width: 216, height: 190),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
        }

        let before = window.frame.origin
        window.sendEvent(try event(.leftMouseDown, CGPoint(x: 100, y: 50)))
        window.sendEvent(try event(.leftMouseDragged, CGPoint(x: 120, y: 70)))
        window.sendEvent(try event(.leftMouseUp, CGPoint(x: 100, y: 50)))
        XCTAssertEqual(window.frame.origin, CGPoint(x: before.x + 20, y: before.y + 20))
        let afterDrag = window.frame.origin
        window.ignoresMouseEvents = true
        window.sendEvent(try event(.leftMouseDown, CGPoint(x: 100, y: 50)))
        window.sendEvent(try event(.leftMouseDragged, CGPoint(x: 140, y: 90)))
        window.sendEvent(try event(.leftMouseUp, CGPoint(x: 100, y: 50)))
        XCTAssertEqual(window.frame.origin, afterDrag)
        XCTAssertFalse(window.canBecomeKey)
        window.ignoresMouseEvents = false
        window.sendEvent(try event(.leftMouseDown, CGPoint(x: 100, y: 50)))
        window.sendEvent(try event(.leftMouseDragged, CGPoint(x: 110, y: 60)))
        window.sendEvent(try event(.leftMouseUp, CGPoint(x: 100, y: 50)))
        XCTAssertEqual(window.frame.origin, CGPoint(x: afterDrag.x + 10, y: afterDrag.y + 10))
        XCTAssertTrue(window.canBecomeKey)
    }

    @MainActor
    func testControllerRestoresInteractionHidesShowsAndPersistsMovement() throws {
        _ = NSApplication.shared
        let suite = "WindowInteractionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        let store = QuotaStore(
            preferences: preferences, snapshotStore: RateLimitSnapshotStore(snapshotURL: cacheURL),
            autostartService: AutostartService(),
            client: CodexAppServerClientMac(locator: CodexExecutableLocatorMac()))
        let controller = FloatingWindowController(preferences: preferences)
        controller.attach(store: store)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hideWindow() }

        controller.showWindow()
        XCTAssertTrue(controller.isWindowVisible)
        controller.setClickThroughEnabled(true)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(preferences.clickThroughEnabled)
        XCTAssertEqual(window.level, .normal)
        controller.setClickThroughEnabled(false)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(preferences.clickThroughEnabled)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.isMovable)
        XCTAssertEqual(window.identifier?.rawValue, "quota-panel")

        controller.hideWindow()
        XCTAssertFalse(controller.isWindowVisible)
        controller.showWindow()
        XCTAssertTrue(controller.isWindowVisible)
        let before = window.frame
        window.setFrameOrigin(CGPoint(x: before.minX - 30, y: before.minY - 30))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: window))
        XCTAssertEqual(preferences.loadWindowPlacement()?.cgRect, window.frame)
        controller.hideWindow()
        let restored = FloatingWindowController(preferences: preferences)
        restored.attach(store: store)
        XCTAssertEqual(restored.window?.frame.origin, window.frame.origin)
        restored.hideWindow()
    }
}
