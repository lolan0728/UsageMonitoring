import AppKit
import Combine
import SwiftUI

private final class FloatingPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FloatingWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isWindowVisible = false
    @Published private(set) var isClickThroughEnabled = false

    private let preferences: AppPreferences
    private var window: NSWindow?
    private weak var store: QuotaStore?
    private var isObservingApplicationVisibility = false
    private var isObservingClickThroughPreference = false
    private static let windowSize = CGSize(width: 216, height: 190)

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.isClickThroughEnabled = preferences.clickThroughEnabled
    }

    func attach(store: QuotaStore) {
        guard window == nil else {
            return
        }

        self.store = store

        let contentView = MainQuotaView(
            store: store,
            windowController: self,
            onHide: { [weak self] in
                self?.hideApplication()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            })
        let hostingController = NSHostingController(rootView: contentView)
        let initialFrame = Self.normalizedFrame(from: preferences.loadWindowPlacement()?.cgRect)

        let window = FloatingPanelWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)

        window.contentViewController = hostingController
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.delegate = self
        window.minSize = Self.windowSize
        window.maxSize = Self.windowSize
        applyClickThroughState(to: window)

        self.window = window
        observeApplicationVisibility()
        observeClickThroughPreferenceChanges()
        syncWindowVisibility()
    }

    func showWindow() {
        guard let window else {
            return
        }

        if preferences.loadWindowPlacement() == nil {
            window.setFrame(Self.defaultFrame(for: window), display: false)
        }

        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        if isClickThroughEnabled {
            window.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        syncWindowVisibility()
    }

    func hideWindow() {
        guard let window else {
            return
        }

        window.orderOut(nil)
        syncWindowVisibility()
    }

    func hideApplication() {
        NSApp.hide(nil)
        syncWindowVisibility()
    }

    func toggleWindow() {
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    func setClickThroughEnabled(_ enabled: Bool) {
        guard isClickThroughEnabled != enabled else {
            return
        }

        isClickThroughEnabled = enabled
        preferences.clickThroughEnabled = enabled

        if let window {
            applyClickThroughState(to: window)
        }

        NotificationCenter.default.post(name: .clickThroughPreferenceDidChange, object: nil)
    }

    func toggleClickThrough() {
        setClickThroughEnabled(!isClickThroughEnabled)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        persistWindowPlacement()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistWindowPlacement()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncWindowVisibility()
    }

    func windowDidResignKey(_ notification: Notification) {
        syncWindowVisibility()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        syncWindowVisibility()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        syncWindowVisibility()
    }

    private func persistWindowPlacement() {
        guard let window else {
            return
        }

        preferences.saveWindowPlacement(WindowPlacement(frame: Self.normalizedFrame(from: window.frame)))
    }

    private static func defaultFrame(for window: NSWindow? = nil) -> CGRect {
        let size = windowSize
        let visibleFrame = window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visibleFrame.maxX - size.width - 24
        let y = visibleFrame.maxY - size.height - 24
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func normalizedFrame(from savedFrame: CGRect?) -> CGRect {
        guard let savedFrame else {
            return defaultFrame()
        }

        return CGRect(origin: savedFrame.origin, size: windowSize)
    }

    private func observeApplicationVisibility() {
        guard !isObservingApplicationVisibility else {
            return
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleApplicationVisibilityChange(_:)), name: NSApplication.didHideNotification, object: NSApp)
        center.addObserver(self, selector: #selector(handleApplicationVisibilityChange(_:)), name: NSApplication.didUnhideNotification, object: NSApp)
        isObservingApplicationVisibility = true
    }

    private func syncWindowVisibility() {
        isWindowVisible = (window?.isVisible ?? false) && !NSApp.isHidden
    }

    private func applyClickThroughState(to window: NSWindow) {
        window.ignoresMouseEvents = isClickThroughEnabled
        window.level = isClickThroughEnabled ? .normal : .floating
    }

    @objc
    private func handleApplicationVisibilityChange(_ notification: Notification) {
        syncWindowVisibility()
    }

    private func observeClickThroughPreferenceChanges() {
        guard !isObservingClickThroughPreference else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClickThroughPreferenceChange(_:)),
            name: .clickThroughPreferenceDidChange,
            object: nil)
        isObservingClickThroughPreference = true
    }

    @objc
    private func handleClickThroughPreferenceChange(_ notification: Notification) {
        setClickThroughEnabled(preferences.clickThroughEnabled)
    }
}
