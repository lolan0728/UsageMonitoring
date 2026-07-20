import Foundation

struct CodexQuotaParseResult: Sendable {
    let snapshot: CodexQuotaSnapshot
    let affectedLimitIds: Set<String>
    let replacesAllLimits: Bool
    let creditsWereProvided: Bool
    let planTypeWasProvided: Bool
    let limitPatches: [CodexQuotaLimitPatch]
}

struct CodexQuotaLimitPatch: Sendable {
    let limitId: String?
    let providedWindowRoles: Set<String>
    let removesAllWindows: Bool
}

enum CodexQuotaParser {
    enum ParserError: Error {
        case missingQuotaPayload
    }

    static func parse(data: Data, syncedAt: Date = Date()) throws -> CodexQuotaParseResult {
        let payload = try JSONDecoder().decode(CodexQuotaResponsePayload.self, from: data)
        return try parse(payload: payload, syncedAt: syncedAt)
    }

    private static func parse(
        payload: CodexQuotaResponsePayload,
        syncedAt: Date
    ) throws -> CodexQuotaParseResult {
        let entries: [(fallbackLimitId: String?, payload: RateLimitSnapshotPayload)]
        let replacesAllLimits: Bool

        if let limitsById = payload.rateLimitsByLimitId, !limitsById.isEmpty {
            entries = limitsById.keys.sorted().compactMap { key in
                limitsById[key].map { (key, $0) }
            }
            replacesAllLimits = false
        } else if let rateLimits = payload.rateLimits {
            entries = [(rateLimits.limitId, rateLimits)]
            replacesAllLimits = normalized(rateLimits.limitId) == nil
        } else if let directRateLimits = payload.directRateLimits {
            entries = [(directRateLimits.limitId, directRateLimits)]
            replacesAllLimits = normalized(directRateLimits.limitId) == nil
        } else if payload.credits != nil || payload.planType != nil {
            entries = []
            replacesAllLimits = true
        } else {
            throw ParserError.missingQuotaPayload
        }

        var limits: [RateLimitBucket] = []
        var seenBucketIds = Set<String>()
        var affectedLimitIds = Set<String>()
        var creditStatuses: [CreditStatus] = []
        var planTypes: [String] = []
        var limitPatches: [CodexQuotaLimitPatch] = []
        var creditsWereProvided = payload.credits != nil
        var planTypeWasProvided = payload.planType != nil

        if let credits = payload.credits?.domainValue {
            creditStatuses.append(credits)
        }
        if let planType = normalized(payload.planType) {
            planTypes.append(planType)
        }

        for entry in entries {
            let limitId = normalized(entry.payload.limitId) ?? normalized(entry.fallbackLimitId)
            let limitName = normalized(entry.payload.limitName)

            if let fallbackLimitId = normalized(entry.fallbackLimitId) {
                affectedLimitIds.insert(fallbackLimitId)
            }
            if let limitId {
                affectedLimitIds.insert(limitId)
            }

            if entry.payload.credits != nil {
                creditsWereProvided = true
            }
            if let credits = entry.payload.credits?.domainValue {
                creditStatuses.append(credits)
            }

            if entry.payload.planType != nil {
                planTypeWasProvided = true
            }
            if let planType = normalized(entry.payload.planType) {
                planTypes.append(planType)
            }

            let windows: [(role: String, payload: RateLimitWindowPayload?)] = [
                ("primary", entry.payload.primary),
                ("secondary", entry.payload.secondary)
            ]
            let providedWindowRoles = Set(windows.compactMap { window in
                window.payload == nil ? nil : window.role
            })
            limitPatches.append(
                CodexQuotaLimitPatch(
                    limitId: limitId,
                    providedWindowRoles: providedWindowRoles,
                    removesAllWindows: providedWindowRoles.isEmpty
                        && entry.payload.credits?.domainValue.unlimited == true))

            for window in windows {
                guard let windowPayload = window.payload,
                      let bucket = makeBucket(
                        payload: windowPayload,
                        role: window.role,
                        limitId: limitId,
                        limitName: limitName,
                        syncedAt: syncedAt),
                      seenBucketIds.insert(bucket.id).inserted
                else {
                    continue
                }

                limits.append(bucket)
            }
        }

        limits.sort(by: compareBuckets)

        return CodexQuotaParseResult(
            snapshot: CodexQuotaSnapshot(
                limits: limits,
                credits: mergeCredits(creditStatuses),
                planType: planTypes.first,
                syncedAt: syncedAt),
            affectedLimitIds: affectedLimitIds,
            replacesAllLimits: replacesAllLimits,
            creditsWereProvided: creditsWereProvided,
            planTypeWasProvided: planTypeWasProvided,
            limitPatches: limitPatches)
    }

    private static func makeBucket(
        payload: RateLimitWindowPayload,
        role: String,
        limitId: String?,
        limitName: String?,
        syncedAt: Date
    ) -> RateLimitBucket? {
        let rawUsedPercent: Double
        if let usedPercent = payload.usedPercent, usedPercent.isFinite {
            rawUsedPercent = usedPercent
        } else if let remainingPercent = payload.remainingPercent, remainingPercent.isFinite {
            rawUsedPercent = 100 - remainingPercent
        } else {
            return nil
        }

        let usedPercent = clampPercent(rawUsedPercent)
        let remainingPercent = clampPercent(100 - usedPercent)
        let duration = payload.windowDurationMins.flatMap { $0 > 0 ? $0 : nil }
        let bucketId = [limitId ?? "_", role, duration.map(String.init) ?? "_"]
            .joined(separator: "|")

        return RateLimitBucket(
            id: bucketId,
            label: buildWindowLabel(duration: duration, limitName: limitName, limitId: limitId),
            windowDurationMins: duration,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetsAt: resetDate(from: payload.resetsAt),
            syncedAt: syncedAt,
            limitId: limitId,
            limitName: limitName,
            windowRole: role)
    }

    private static func buildWindowLabel(duration: Int?, limitName: String?, limitId: String?) -> String {
        guard let duration else {
            return normalized(limitName) ?? normalized(limitId) ?? "Usage"
        }

        switch duration {
        case 300:
            return "5h"
        case 10080:
            return "1w"
        case 43200:
            return "1mo"
        case let value where value >= 10080 && value.isMultiple(of: 10080):
            return "\(value / 10080)w"
        case let value where value >= 1440 && value.isMultiple(of: 1440):
            return "\(value / 1440)d"
        case let value where value >= 60 && value.isMultiple(of: 60):
            return "\(value / 60)h"
        default:
            return "\(duration)m"
        }
    }

    private static func resetDate(from timestamp: Int64?) -> Date? {
        guard let timestamp else {
            return nil
        }

        let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1_000 : Double(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }

    private static func mergeCredits(_ statuses: [CreditStatus]) -> CreditStatus? {
        guard !statuses.isEmpty else {
            return nil
        }

        let unlimited = statuses.contains(where: \.unlimited)
        let hasCredits = statuses.contains(where: \.hasCredits)
        let balance = statuses.first(where: {
            ($0.unlimited || $0.hasCredits) && normalized($0.balance) != nil
        })?.balance ?? statuses.first(where: { normalized($0.balance) != nil })?.balance
        return CreditStatus(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }

    private static func compareBuckets(_ lhs: RateLimitBucket, _ rhs: RateLimitBucket) -> Bool {
        switch (lhs.windowDurationMins, rhs.windowDurationMins) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            if lhs.label != rhs.label {
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private static func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct CodexQuotaResponsePayload: Decodable {
    let rateLimitsByLimitId: [String: RateLimitSnapshotPayload]?
    let rateLimits: RateLimitSnapshotPayload?
    let credits: CreditStatusPayload?
    let planType: String?
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
    let limitId: String?
    let limitName: String?

    var directRateLimits: RateLimitSnapshotPayload? {
        guard primary != nil || secondary != nil || limitId != nil || limitName != nil else {
            return nil
        }

        return RateLimitSnapshotPayload(
            primary: primary,
            secondary: secondary,
            credits: credits,
            planType: planType,
            limitId: limitId,
            limitName: limitName)
    }
}

private struct RateLimitSnapshotPayload: Decodable {
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
    let credits: CreditStatusPayload?
    let planType: String?
    let limitId: String?
    let limitName: String?
}

private struct RateLimitWindowPayload: Decodable {
    let windowDurationMins: Int?
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case windowDurationMins
        case usedPercent
        case remainingPercent
        case resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowDurationMins = container.flexibleInt(forKey: .windowDurationMins)
        usedPercent = container.flexibleDouble(forKey: .usedPercent)
        remainingPercent = container.flexibleDouble(forKey: .remainingPercent)
        resetsAt = container.flexibleInt64(forKey: .resetsAt)
    }
}

private struct CreditStatusPayload: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?

    var domainValue: CreditStatus {
        CreditStatus(
            hasCredits: hasCredits ?? false,
            unlimited: unlimited ?? false,
            balance: balance)
    }

    private enum CodingKeys: String, CodingKey {
        case hasCredits
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = container.flexibleBool(forKey: .hasCredits)
        unlimited = container.flexibleBool(forKey: .unlimited)
        balance = container.flexibleString(forKey: .balance)
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            guard value.isFinite,
                  value >= Double(Int.min),
                  value < Double(Int.max)
            else {
                return nil
            }
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func flexibleInt64(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            guard value.isFinite,
                  value >= Double(Int64.min),
                  value < Double(Int64.max)
            else {
                return nil
            }
            return Int64(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    func flexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func flexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}
