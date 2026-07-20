import Foundation

struct CreditStatus: Codable, Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    var shouldDisplay: Bool {
        unlimited || hasCredits
    }
}

struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    var limits: [RateLimitBucket]
    var credits: CreditStatus?
    var planType: String?
    var syncedAt: Date

    var hasDisplayableUsage: Bool {
        !limits.isEmpty || credits?.shouldDisplay == true
    }
}
