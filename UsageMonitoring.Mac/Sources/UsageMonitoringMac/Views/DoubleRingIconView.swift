import SwiftUI

struct DoubleRingIconView: View {
    let isLive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color(red: 36.0 / 255.0, green: 36.0 / 255.0, blue: 38.0 / 255.0))
                .frame(width: 18, height: 18)

            Circle()
                .trim(from: 0.12, to: 0.73)
                .stroke(primaryRing, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 13.5, height: 13.5)

            Circle()
                .trim(from: 0.48, to: 0.97)
                .stroke(secondaryRing, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 8.5, height: 8.5)

            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(centerBlock)
                .frame(width: 3.2, height: 3.2)
        }
    }

    private var primaryRing: Color {
        isLive
            ? Color(red: 18.0 / 255.0, green: 1.0, blue: 166.0 / 255.0)
            : Color(red: 94.0 / 255.0, green: 157.0 / 255.0, blue: 134.0 / 255.0)
    }

    private var secondaryRing: Color {
        isLive
            ? Color(red: 95.0 / 255.0, green: 232.0 / 255.0, blue: 1.0)
            : Color(red: 108.0 / 255.0, green: 148.0 / 255.0, blue: 158.0 / 255.0)
    }

    private var centerBlock: Color {
        Color.white.opacity(isLive ? 0.96 : 0.62)
    }
}
