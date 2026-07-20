import Foundation

struct QuotaCardDisplay: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case rateLimit
        case credits
        case unavailable
    }

    enum Accent: Equatable, Sendable {
        case primary
        case secondary
        case credits
        case unavailable
    }

    let id: String
    let kind: Kind
    let accent: Accent
    let label: String
    let valueText: String
    let detailText: String
    let statusText: String
    let progressPercent: Double?

    static func unavailable(statusText: String = "Unavailable") -> QuotaCardDisplay {
        QuotaCardDisplay(
            id: "usage-unavailable",
            kind: .unavailable,
            accent: .unavailable,
            label: "Usage",
            valueText: "--",
            detailText: "Unavailable",
            statusText: statusText,
            progressPercent: nil)
    }
}

@MainActor
enum QuotaCardFactory {
    static func makeCards(snapshot: CodexQuotaSnapshot?) -> [QuotaCardDisplay] {
        guard let snapshot else {
            return [.unavailable()]
        }

        var cards = snapshot.limits.enumerated().map { index, bucket in
            QuotaCardDisplay(
                id: bucket.id,
                kind: .rateLimit,
                accent: accent(for: bucket, index: index),
                label: bucket.label,
                valueText: "\(Int(bucket.remainingPercent.rounded()))%",
                detailText: resetText(for: bucket),
                statusText: "\(Int(bucket.usedPercent.rounded()))% used",
                progressPercent: bucket.remainingPercent)
        }

        if let credits = snapshot.credits, credits.shouldDisplay {
            cards.append(
                QuotaCardDisplay(
                    id: "credits",
                    kind: .credits,
                    accent: .credits,
                    label: "Credits",
                    valueText: credits.unlimited ? "∞" : (credits.balance ?? "--"),
                    detailText: credits.unlimited ? "Unlimited" : "Available",
                    statusText: credits.unlimited ? "Unlimited" : "Credits available",
                    progressPercent: nil))
        }

        return cards.isEmpty ? [.unavailable()] : cards
    }

    private static func accent(for bucket: RateLimitBucket, index: Int) -> QuotaCardDisplay.Accent {
        switch bucket.windowDurationMins {
        case 300:
            return .primary
        case 10080:
            return .secondary
        default:
            return index.isMultiple(of: 2) ? .primary : .secondary
        }
    }

    private static func resetText(for bucket: RateLimitBucket) -> String {
        guard let resetsAt = bucket.resetsAt else {
            return "Until --"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = (bucket.windowDurationMins ?? 1440) < 1440 ? "HH:mm" : "MM-dd HH:mm"
        return "Until \(formatter.string(from: resetsAt))"
    }
}
