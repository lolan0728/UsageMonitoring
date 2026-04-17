import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var windowController: FloatingWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                windowController.toggleWindow()
            } label: {
                Label(
                    windowController.isWindowVisible ? "Hide Window" : "Show Window",
                    systemImage: windowController.isWindowVisible ? MenuIcons.hideSystemName : "eye")
            }

            Button {
                windowController.toggleClickThrough()
            } label: {
                Label(
                    "Click Through",
                    systemImage: windowController.isClickThroughEnabled
                        ? MenuIcons.clickThroughEnabledSystemName
                        : MenuIcons.clickThroughDisabledSystemName)
            }

            Button {
                store.locateCodexInteractively()
            } label: {
                Label("Locate Codex", systemImage: "folder")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: MenuIcons.quitSystemName)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
