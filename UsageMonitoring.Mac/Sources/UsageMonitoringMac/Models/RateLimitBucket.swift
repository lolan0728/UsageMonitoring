import Foundation

struct RateLimitBucket: Codable, Identifiable, Equatable, Sendable {
    let label: String
    let windowDurationMins: Int
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAtUtc: Date?
    let syncedAtUtc: Date
    let limitId: String?
    let limitName: String?

    var id: Int { windowDurationMins }
}
