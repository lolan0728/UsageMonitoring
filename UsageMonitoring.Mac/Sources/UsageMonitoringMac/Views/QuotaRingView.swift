import SwiftUI

struct QuotaRingView: View {
    let remainingPercent: Double
    let ringColor: Color
    let trackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor.opacity(0.72),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .blur(radius: 8)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor.opacity(0.3),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .blur(radius: 12)
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 78, height: 78)
    }

    private var progress: Double {
        max(0, min(1, remainingPercent / 100))
    }
}

struct QuotaStatusRingView: View {
    let ringColor: Color
    let trackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))

            Circle()
                .stroke(ringColor.opacity(0.34), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .blur(radius: 12)

            Circle()
                .stroke(ringColor.opacity(0.72), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .blur(radius: 8)

            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))

            Circle()
                .fill(ringColor.opacity(0.9))
                .frame(width: 12, height: 12)
        }
        .frame(width: 78, height: 78)
    }
}
