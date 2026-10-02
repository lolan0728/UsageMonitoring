import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let aboutWindowController = AboutWindowController()
    private let preferences = AppPreferences()
    private var quotaStore: QuotaStore?
    private var floatingWindowController: FloatingWindowController?
    private var cachedAppName: String?
    private var cachedApplicationMenu: NSMenu?
    private var appMenuClickThroughItem: NSMenuItem?
    private var isObservingMainMenu = false
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startApplication()
    }

    func startApplication() {
        guard quotaStore == nil else { return }
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        startObservingMainMenuMutations()
        startObservingClickThroughMutations()
        let client = CodexAppServerClientMac(
            locator: CodexExecutableLocatorMac(),
            preferredExecutablePath: preferences.codexExecutablePath)
        let store = QuotaStore(
            preferences: preferences,
            snapshotStore: RateLimitSnapshotStore(),
            autostartService: AutostartService(),
            client: client)
        let controller = FloatingWindowController(preferences: preferences)
        quotaStore = store
        floatingWindowController = controller
        controller.attach(store: store)
        controller.showWindow()
        installStatusMenu()
        Task {
            await store.start()
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        stripToApplicationMenuOnly()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        stripToApplicationMenuOnly()
    }

    func applicationWillUpdate(_ notification: Notification) {
        // SwiftUI sometimes re-attaches menus during update passes.
        stripToApplicationMenuOnly()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        floatingWindowController?.showWindow()
        return false
    }

    @objc
    func showAboutWindow(_ sender: Any?) {
        aboutWindowController.show()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        buildDockMenu()
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.donut", accessibilityDescription: "Usage Monitoring")
        item.button?.image?.isTemplate = true
        let menu = NSMenu(title: "Usage Monitoring")
        appendControls(to: menu)
        menu.addItem(.separator())
        addItem("About Usage Monitoring", action: #selector(showAboutWindow(_:)), to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func appendControls(to menu: NSMenu) {
        menu.delegate = self
        let status = NSMenuItem(title: quotaStore?.connectionStatusText ?? "Waiting for Codex", action: nil, keyEquivalent: "")
        status.tag = 100
        menu.addItem(status)
        addItem("Show Window", action: #selector(toggleQuotaWindow(_:)), to: menu)
        addItem("Click Through", action: #selector(toggleClickThroughFromDock(_:)), to: menu)
        menu.addItem(.separator())
        addItem("Refresh Quota", action: #selector(refreshQuota(_:)), to: menu)
        addItem("Reconnect Codex", action: #selector(reconnectCodex(_:)), to: menu)
        addItem("Locate Codex…", action: #selector(locateCodex(_:)), to: menu)
        menu.addItem(.separator())
        addItem("Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), to: menu)
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if item.tag == 100 {
                item.title = quotaStore?.connectionStatusText ?? "Waiting for Codex"
            } else if item.action == #selector(toggleQuotaWindow(_:)) {
                item.title = floatingWindowController?.isWindowVisible == true ? "Hide Window" : "Show Window"
            } else if item.action == #selector(toggleClickThroughFromDock(_:)) {
                item.state = preferences.clickThroughEnabled ? .on : .off
            } else if item.action == #selector(toggleLaunchAtLogin(_:)) {
                item.state = quotaStore?.launchAtLogin == true ? .on : .off
            }
        }
    }

    @objc private func toggleQuotaWindow(_ sender: Any?) { floatingWindowController?.toggleWindow() }
    @objc private func refreshQuota(_ sender: Any?) {
        Task { await quotaStore?.refreshNow() }
    }
    @objc private func reconnectCodex(_ sender: Any?) {
        Task { await quotaStore?.reconnect() }
    }
    @objc private func locateCodex(_ sender: Any?) { quotaStore?.locateCodexInteractively() }
    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        guard let store = quotaStore else { return }
        store.setLaunchAtLogin(!store.launchAtLogin)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = applicationMenu()
        NSApp.mainMenu = mainMenu
    }

    private func stripToApplicationMenuOnly() {
        guard let mainMenu = NSApp.mainMenu else {
            installMainMenu()
            return
        }

        // Ensure first item is our app menu.
        if mainMenu.items.isEmpty {
            installMainMenu()
            return
        }

        let appMenu = applicationMenu()
        if mainMenu.items[0].submenu !== appMenu {
            mainMenu.items[0].submenu = appMenu
        }

        // Remove everything else (View / Window / Help, etc.).
        if mainMenu.items.count > 1 {
            for item in mainMenu.items.dropFirst() {
                mainMenu.removeItem(item)
            }
        }
    }

    private func startObservingMainMenuMutations() {
        guard !isObservingMainMenu else { return }
        isObservingMainMenu = true

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleMainMenuMutation(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(handleMainMenuMutation(_:)),
            name: NSMenu.didChangeItemNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(handleMainMenuMutation(_:)),
            name: NSMenu.didRemoveItemNotification,
            object: nil)
    }

    private func startObservingClickThroughMutations() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClickThroughMutation(_:)),
            name: .clickThroughPreferenceDidChange,
            object: nil)
    }

    @objc
    private func handleMainMenuMutation(_ notification: Notification) {
        // Any time the main menu changes, immediately re-strip to prevent flashes.
        guard let mainMenu = NSApp.mainMenu else { return }
        if let menu = notification.object as? NSMenu, menu === mainMenu {
            stripToApplicationMenuOnly()
        }
    }

    @objc
    private func handleClickThroughMutation(_ notification: Notification) {
        refreshAppMenuClickThroughPresentation()
    }

    private func resolvedAppName() -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return "Usage Monitoring"
    }

    private func applicationMenu() -> NSMenu {
        let name = resolvedAppName()
        if cachedAppName == name, let cachedApplicationMenu {
            refreshAppMenuClickThroughPresentation()
            return cachedApplicationMenu
        }
        let menu = buildApplicationMenu(appName: name)
        cachedAppName = name
        cachedApplicationMenu = menu
        return menu
    }

    private func buildApplicationMenu(appName: String) -> NSMenu {
        let menu = NSMenu(title: appName)

        let aboutItem = NSMenuItem(
            title: "About \(appName)",
            action: #selector(showAboutWindow(_:)),
            keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        hideItem.target = NSApp
        hideItem.image = MenuIcons.hideImage
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let clickThroughItem = NSMenuItem(
            title: "Click Through",
            action: #selector(toggleClickThroughFromDock(_:)),
            keyEquivalent: "")
        clickThroughItem.target = self
        clickThroughItem.state = preferences.clickThroughEnabled ? .on : .off
        clickThroughItem.image = MenuIcons.clickThroughImage(enabled: preferences.clickThroughEnabled)
        menu.addItem(clickThroughItem)
        appMenuClickThroughItem = clickThroughItem

        addItem("Show Window", action: #selector(toggleQuotaWindow(_:)), to: menu)
        addItem("Refresh Quota", action: #selector(refreshQuota(_:)), to: menu)
        addItem("Reconnect Codex", action: #selector(reconnectCodex(_:)), to: menu)
        addItem("Locate Codex…", action: #selector(locateCodex(_:)), to: menu)
        addItem("Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), to: menu)
        menu.delegate = self

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.image = MenuIcons.quitImage
        menu.addItem(quitItem)

        return menu
    }

    private func buildDockMenu() -> NSMenu {
        let appName = resolvedAppName()
        let menu = NSMenu(title: appName)

        appendControls(to: menu)

        return menu
    }

    @objc
    private func toggleClickThroughFromDock(_ sender: Any?) {
        floatingWindowController?.toggleClickThrough()
    }

    private func refreshAppMenuClickThroughPresentation() {
        if let menu = cachedApplicationMenu {
            menuNeedsUpdate(menu)
        }
        if let menu = statusItem?.menu {
            menuNeedsUpdate(menu)
        }
        guard let appMenuClickThroughItem else {
            return
        }

        let isEnabled = preferences.clickThroughEnabled
        appMenuClickThroughItem.state = isEnabled ? .on : .off
        appMenuClickThroughItem.title = "Click Through"
        appMenuClickThroughItem.image = MenuIcons.clickThroughImage(enabled: isEnabled)
    }
}
