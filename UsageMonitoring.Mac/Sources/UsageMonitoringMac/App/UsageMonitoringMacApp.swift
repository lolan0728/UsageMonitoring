import AppKit
import SwiftUI

@main
struct UsageMonitoringMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: QuotaStore
    @StateObject private var windowController: FloatingWindowController

    init() {
        let preferences = AppPreferences()
        let locator = CodexExecutableLocatorMac()
        let client = CodexAppServerClientMac(
            locator: locator,
            preferredExecutablePath: preferences.codexExecutablePath)
        let snapshotStore = RateLimitSnapshotStore()
        let autostartService = AutostartService()
        let store = QuotaStore(
            preferences: preferences,
            snapshotStore: snapshotStore,
            autostartService: autostartService,
            client: client)
        let windowController = FloatingWindowController(preferences: preferences)

        _store = StateObject(wrappedValue: store)
        _windowController = StateObject(wrappedValue: windowController)

        Task { @MainActor in
            windowController.attach(store: store)
            windowController.showWindow()
            await store.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Remove default SwiftUI macOS menus (View / Window / Help).
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowArrangement) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
        }
    }
}
