import Foundation

struct RateLimitBucket: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let windowDurationMins: Int?
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?
    let syncedAt: Date
    let limitId: String?
    let limitName: String?
    let windowRole: String?
}
