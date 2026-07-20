import CoreGraphics

enum QuotaPanelLayout {
    static let width: CGFloat = 216
    static let heightPerCard: CGFloat = 95
    static let logicalWidth: CGFloat = 334
    static let logicalCardHeight: CGFloat = 146
    static let logicalCardSpacing: CGFloat = 8

    static func windowSize(cardCount: Int) -> CGSize {
        CGSize(width: width, height: heightPerCard * CGFloat(max(1, cardCount)))
    }

    static func logicalHeight(cardCount: Int) -> CGFloat {
        let count = CGFloat(max(1, cardCount))
        return logicalCardHeight * count + logicalCardSpacing * (count - 1)
    }

    static func resizedFrame(from oldFrame: CGRect, to requestedSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: min(requestedSize.width, visibleFrame.width),
            height: min(requestedSize.height, visibleFrame.height))
        let topDistance = abs(visibleFrame.maxY - oldFrame.maxY)
        let bottomDistance = abs(oldFrame.minY - visibleFrame.minY)
        let proposedY = topDistance <= bottomDistance
            ? oldFrame.maxY - size.height
            : oldFrame.minY
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height

        return CGRect(
            x: min(max(oldFrame.minX, visibleFrame.minX), maxX),
            y: min(max(proposedY, visibleFrame.minY), maxY),
            width: size.width,
            height: size.height)
    }
}
