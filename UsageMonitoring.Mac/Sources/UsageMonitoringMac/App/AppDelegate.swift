import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let aboutWindowController = AboutWindowController()
    private var cachedAppName: String?
    private var cachedApplicationMenu: NSMenu?
    private var isObservingMainMenu = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        startObservingMainMenuMutations()
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
        if !flag {
            sender.activate(ignoringOtherApps: true)
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }

        return true
    }

    @objc
    func showAboutWindow(_ sender: Any?) {
        aboutWindowController.show()
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

    @objc
    private func handleMainMenuMutation(_ notification: Notification) {
        // Any time the main menu changes, immediately re-strip to prevent flashes.
        guard let mainMenu = NSApp.mainMenu else { return }
        if let menu = notification.object as? NSMenu, menu === mainMenu {
            stripToApplicationMenuOnly()
        }
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
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }
}
