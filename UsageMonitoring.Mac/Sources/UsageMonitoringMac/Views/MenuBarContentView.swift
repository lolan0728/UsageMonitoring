import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var windowController: FloatingWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(windowController.isWindowVisible ? "Hide Window" : "Show Window") {
                windowController.toggleWindow()
            }

            Button("Locate Codex") {
                store.locateCodexInteractively()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
