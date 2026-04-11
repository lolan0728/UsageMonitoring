import SwiftUI

struct QuotaPillView: View {
    let card: QuotaCardViewData
    let isLive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(pillBackground.opacity(isLive ? 1.0 : 0.94))
                .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 6)

            HStack(spacing: 10) {
                ZStack {
                    QuotaRingView(
                        remainingPercent: card.remainingPercent,
                        ringColor: ringColor,
                        trackColor: trackColor)
                }
                .frame(width: 90, alignment: .center)

                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)

                        Text(card.label)
                            .font(.custom("Segoe UI Semibold", size: 15))
                            .foregroundStyle(labelText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Spacer(minLength: 0)

                    VStack(spacing: 6) {
                        Text(card.remainingText)
                            .font(.custom("Segoe UI Semibold", size: 40))
                            .monospacedDigit()
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .shadow(color: isLive ? ringColor.opacity(0.18) : .clear, radius: 6, x: 0, y: 0)

                        Text(card.resetText)
                            .font(.custom("Segoe UI Semibold", size: 18))
                            .foregroundStyle(subtitleText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 294, height: 114)
    }

    private var pillBackground: Color {
        Color(red: 74.0 / 255.0, green: 74.0 / 255.0, blue: 74.0 / 255.0)
    }

    private var ringColor: Color {
        if card.label == "5h" {
            return isLive
                ? Color(red: 18.0 / 255.0, green: 1.0, blue: 166.0 / 255.0)
                : Color(red: 94.0 / 255.0, green: 157.0 / 255.0, blue: 134.0 / 255.0)
        }

        return isLive
            ? Color(red: 95.0 / 255.0, green: 232.0 / 255.0, blue: 1.0)
            : Color(red: 108.0 / 255.0, green: 148.0 / 255.0, blue: 158.0 / 255.0)
    }

    private var trackColor: Color {
        if card.label == "5h" {
            return isLive
                ? Color(red: 50.0 / 255.0, green: 117.0 / 255.0, blue: 90.0 / 255.0)
                : Color(red: 38.0 / 255.0, green: 56.0 / 255.0, blue: 47.0 / 255.0)
        }

        return isLive
            ? Color(red: 45.0 / 255.0, green: 101.0 / 255.0, blue: 112.0 / 255.0)
            : Color(red: 36.0 / 255.0, green: 55.0 / 255.0, blue: 59.0 / 255.0)
    }

    private var primaryText: Color {
        isLive
            ? .white
            : Color(red: 197.0 / 255.0, green: 206.0 / 255.0, blue: 206.0 / 255.0, opacity: 150.0 / 255.0)
    }

    private var labelText: Color {
        isLive
            ? Color(red: 239.0 / 255.0, green: 239.0 / 255.0, blue: 239.0 / 255.0, opacity: 235.0 / 255.0)
            : Color(red: 161.0 / 255.0, green: 165.0 / 255.0, blue: 165.0 / 255.0, opacity: 112.0 / 255.0)
    }

    private var subtitleText: Color {
        isLive
            ? Color(red: 241.0 / 255.0, green: 243.0 / 255.0, blue: 244.0 / 255.0, opacity: 0.98)
            : Color(red: 160.0 / 255.0, green: 164.0 / 255.0, blue: 166.0 / 255.0, opacity: 118.0 / 255.0)
    }
}
