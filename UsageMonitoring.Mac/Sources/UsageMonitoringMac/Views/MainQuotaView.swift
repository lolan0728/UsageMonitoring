import SwiftUI

struct MainQuotaView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var windowController: FloatingWindowController
    let onHide: () -> Void
    let onQuit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let logicalCanvasSize = CGSize(
                width: QuotaPanelLayout.logicalWidth,
                height: QuotaPanelLayout.logicalHeight(cardCount: store.quotaCards.count))
            let scale = min(
                geometry.size.width / logicalCanvasSize.width,
                geometry.size.height / logicalCanvasSize.height)
            let scaledSize = CGSize(
                width: logicalCanvasSize.width * scale,
                height: logicalCanvasSize.height * scale)

            ZStack {
                Color.clear

                VStack(spacing: QuotaPanelLayout.logicalCardSpacing) {
                    ForEach(store.quotaCards) { card in
                        QuotaPillView(
                            card: card,
                            isLive: store.isQuotaLive)
                            .frame(height: QuotaPanelLayout.logicalCardHeight)
                    }
                }
                .frame(width: logicalCanvasSize.width, height: logicalCanvasSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: scaledSize.width, height: scaledSize.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            width: QuotaPanelLayout.width,
            height: QuotaPanelLayout.windowSize(cardCount: store.quotaCards.count).height)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                windowController.toggleClickThrough()
            } label: {
                Label(
                    "Click Through",
                    systemImage: windowController.isClickThroughEnabled
                        ? MenuIcons.clickThroughEnabledSystemName
                        : MenuIcons.clickThroughDisabledSystemName)
            }

            Divider()

            Button {
                onHide()
            } label: {
                Label("Hide", systemImage: MenuIcons.hideSystemName)
            }

            Button {
                onQuit()
            } label: {
                Label("Quit", systemImage: MenuIcons.quitSystemName)
            }
        }
    }
}
