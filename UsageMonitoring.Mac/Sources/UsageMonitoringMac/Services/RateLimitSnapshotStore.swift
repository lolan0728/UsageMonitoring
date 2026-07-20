import Foundation

final class RateLimitSnapshotStore {
    private struct LegacySnapshotDocument: Codable {
        let savedAtUtc: Date
        let buckets: [LegacyRateLimitBucket]
    }

    private struct LegacyFixedQuotaDocument: Codable {
        let fiveHourQuota: LegacyRateLimitBucket?
        let weeklyQuota: LegacyRateLimitBucket?
        let fiveHourBucket: LegacyRateLimitBucket?
        let weeklyBucket: LegacyRateLimitBucket?

        var buckets: [LegacyRateLimitBucket] {
            [fiveHourQuota, weeklyQuota, fiveHourBucket, weeklyBucket].compactMap { $0 }
        }
    }

    private struct LegacyRateLimitBucket: Codable {
        let label: String?
        let windowDurationMins: Int
        let usedPercent: Double
        let remainingPercent: Double
        let resetsAtUtc: Date?
        let syncedAtUtc: Date?
        let limitId: String?
        let limitName: String?
    }

    private let snapshotURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(snapshotURL: URL = AppPaths.rateLimitSnapshotURL) {
        self.snapshotURL = snapshotURL
    }

    func load() -> CodexQuotaSnapshot? {
        ensureDirectoryExists()

        guard let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }

        if let snapshot = try? decoder.decode(CodexQuotaSnapshot.self, from: data),
           snapshot.hasDisplayableUsage {
            return normalized(snapshot)
        }

        if let document = try? decoder.decode(LegacySnapshotDocument.self, from: data) {
            return migrate(document.buckets, fallbackSyncedAt: document.savedAtUtc)
        }

        if let buckets = try? decoder.decode([LegacyRateLimitBucket].self, from: data) {
            return migrate(buckets, fallbackSyncedAt: Date())
        }

        if let document = try? decoder.decode(LegacyFixedQuotaDocument.self, from: data),
           !document.buckets.isEmpty {
            return migrate(document.buckets, fallbackSyncedAt: Date())
        }

        return nil
    }

    func save(_ snapshot: CodexQuotaSnapshot) {
        guard snapshot.hasDisplayableUsage else {
            return
        }

        ensureDirectoryExists()

        guard let data = try? encoder.encode(normalized(snapshot)) else {
            return
        }

        try? data.write(to: snapshotURL, options: .atomic)
    }

    private func migrate(_ legacyBuckets: [LegacyRateLimitBucket], fallbackSyncedAt: Date) -> CodexQuotaSnapshot? {
        var seenIds = Set<String>()
        let buckets = legacyBuckets.compactMap { legacy -> RateLimitBucket? in
            let role = legacy.windowDurationMins == 300 ? "primary" : "secondary"
            let id = [legacy.limitId ?? "legacy", role, String(legacy.windowDurationMins)]
                .joined(separator: "|")
            guard seenIds.insert(id).inserted else {
                return nil
            }

            let used = max(0, min(100, legacy.usedPercent))
            let remaining = max(0, min(100, legacy.remainingPercent))
            return RateLimitBucket(
                id: id,
                label: legacy.label ?? windowLabel(for: legacy.windowDurationMins),
                windowDurationMins: legacy.windowDurationMins,
                usedPercent: used,
                remainingPercent: remaining,
                resetsAt: legacy.resetsAtUtc,
                syncedAt: legacy.syncedAtUtc ?? fallbackSyncedAt,
                limitId: legacy.limitId,
                limitName: legacy.limitName,
                windowRole: role)
        }

        guard !buckets.isEmpty else {
            return nil
        }

        return CodexQuotaSnapshot(
            limits: sort(buckets),
            credits: nil,
            planType: nil,
            syncedAt: buckets.map(\.syncedAt).max() ?? fallbackSyncedAt)
    }

    private func normalized(_ snapshot: CodexQuotaSnapshot) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            limits: sort(snapshot.limits),
            credits: snapshot.credits,
            planType: snapshot.planType,
            syncedAt: snapshot.syncedAt)
    }

    private func sort(_ buckets: [RateLimitBucket]) -> [RateLimitBucket] {
        buckets.sorted { lhs, rhs in
            switch (lhs.windowDurationMins, rhs.windowDurationMins) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.id < rhs.id
            }
        }
    }

    private func windowLabel(for minutes: Int) -> String {
        switch minutes {
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
            return "\(minutes)m"
        }
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }
}
