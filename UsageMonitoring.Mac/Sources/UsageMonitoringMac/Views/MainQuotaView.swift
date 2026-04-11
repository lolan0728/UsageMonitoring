import SwiftUI

struct MainQuotaView: View {
    @ObservedObject var store: QuotaStore
    let onHide: () -> Void
    let onQuit: () -> Void

    private let logicalCanvasSize = CGSize(width: 334, height: 300)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / logicalCanvasSize.width,
                geometry.size.height / logicalCanvasSize.height)
            let scaledSize = CGSize(
                width: logicalCanvasSize.width * scale,
                height: logicalCanvasSize.height * scale)

            ZStack {
                Color.clear

                VStack(spacing: 8) {
                    QuotaPillView(
                        card: store.fiveHourCard,
                        isLive: store.isQuotaLive)
                        .frame(height: 146)

                    QuotaPillView(
                        card: store.weeklyCard,
                        isLive: store.isQuotaLive)
                        .frame(height: 146)
                }
                .frame(width: logicalCanvasSize.width, height: logicalCanvasSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: scaledSize.width, height: scaledSize.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 216, height: 190)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Hide") {
                onHide()
            }

            Button("Quit") {
                onQuit()
            }
        }
    }
}
