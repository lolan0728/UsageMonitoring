import CoreGraphics

struct WindowPlacement: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(frame: CGRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.size.width
        height = frame.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
