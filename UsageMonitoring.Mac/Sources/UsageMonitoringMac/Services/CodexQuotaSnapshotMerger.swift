import Foundation

enum CodexQuotaSnapshotMerger {
    static func merge(
        current: CodexQuotaSnapshot?,
        update: CodexQuotaParseResult
    ) -> CodexQuotaSnapshot {
        guard let current else {
            return update.snapshot
        }

        var retainedLimits = current.limits
        for patch in update.limitPatches {
            retainedLimits.removeAll { bucket in
                guard bucket.limitId == patch.limitId else {
                    return false
                }
                if patch.removesAllWindows {
                    return true
                }
                guard let role = bucket.windowRole else {
                    return false
                }
                return patch.providedWindowRoles.contains(role)
            }
        }

        let updatedLimits = update.snapshot.limits.map { bucket in
            mergeSparseMetadata(for: bucket, from: current.limits)
        }

        return CodexQuotaSnapshot(
            limits: sort(retainedLimits + updatedLimits),
            credits: update.creditsWereProvided ? update.snapshot.credits : current.credits,
            planType: update.planTypeWasProvided ? update.snapshot.planType : current.planType,
            syncedAt: update.snapshot.syncedAt)
    }

    private static func mergeSparseMetadata(
        for bucket: RateLimitBucket,
        from currentLimits: [RateLimitBucket]
    ) -> RateLimitBucket {
        guard bucket.limitName == nil,
              let previous = currentLimits.first(where: {
                $0.limitId == bucket.limitId && $0.windowRole == bucket.windowRole
              }),
              let previousLimitName = previous.limitName
        else {
            return bucket
        }

        return RateLimitBucket(
            id: bucket.id,
            label: bucket.windowDurationMins == nil ? previousLimitName : bucket.label,
            windowDurationMins: bucket.windowDurationMins,
            usedPercent: bucket.usedPercent,
            remainingPercent: bucket.remainingPercent,
            resetsAt: bucket.resetsAt,
            syncedAt: bucket.syncedAt,
            limitId: bucket.limitId,
            limitName: previousLimitName,
            windowRole: bucket.windowRole)
    }

    private static func sort(_ buckets: [RateLimitBucket]) -> [RateLimitBucket] {
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
}
