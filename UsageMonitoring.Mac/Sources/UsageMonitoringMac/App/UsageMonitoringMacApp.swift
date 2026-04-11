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
        MenuBarExtra {
            MenuBarContentView(store: store, windowController: windowController)
        } label: {
            DoubleRingIconView(isLive: store.isQuotaLive)
                .frame(width: 18, height: 18)
        }

        Settings {
            EmptyView()
        }
    }
}
