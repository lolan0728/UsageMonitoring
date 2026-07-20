import Foundation
import XCTest
@testable import UsageMonitoringMac

final class CodexQuotaParserTests: XCTestCase {
    @MainActor
    func testNewPayloadWithOnlyWeeklyLimitAndNoCreditsMakesOneCard() throws {
        let result = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "codex": {
                  "limitId": "codex",
                  "limitName": "Codex",
                  "primary": { "windowDurationMins": 10080, "usedPercent": 27, "resetsAt": 1900000000 },
                  "credits": { "hasCredits": false, "unlimited": false, "balance": "0" }
                }
              }
            }
            """)

        XCTAssertEqual(result.snapshot.limits.map(\.label), ["1w"])
        XCTAssertEqual(result.snapshot.limits.first?.remainingPercent, 73)
        XCTAssertEqual(QuotaCardFactory.makeCards(snapshot: result.snapshot).map(\.label), ["1w"])
    }

    func testLegacyPayloadStillParsesFiveHourAndWeeklyLimits() throws {
        let result = try parse(
            """
            {
              "rateLimits": {
                "primary": { "windowDurationMins": 300, "usedPercent": 20, "resetsAt": 1900000000 },
                "secondary": { "windowDurationMins": 10080, "usedPercent": 40, "resetsAt": 1900000000 }
              }
            }
            """)

        XCTAssertEqual(result.snapshot.limits.map(\.label), ["5h", "1w"])
        XCTAssertTrue(result.replacesAllLimits)
    }

    func testRateLimitsByLimitIdTakesPrecedenceOverLegacyRateLimits() throws {
        let result = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "new": {
                  "primary": { "windowDurationMins": 10080, "usedPercent": 10 }
                }
              },
              "rateLimits": {
                "primary": { "windowDurationMins": 300, "usedPercent": 90 }
              }
            }
            """)

        XCTAssertEqual(result.snapshot.limits.map(\.label), ["1w"])
        XCTAssertEqual(result.affectedLimitIds, ["new"])
    }

    @MainActor
    func testCreditsUseOriginalBalanceAndDoNotCreatePercentage() throws {
        let result = try parse(
            """
            {
              "rateLimits": {
                "primary": { "windowDurationMins": 10080, "usedPercent": 10 },
                "credits": { "hasCredits": true, "unlimited": false, "balance": "12.3400" }
              }
            }
            """)

        let cards = QuotaCardFactory.makeCards(snapshot: result.snapshot)
        XCTAssertEqual(cards.map(\.label), ["1w", "Credits"])
        XCTAssertEqual(cards.last?.valueText, "12.3400")
        XCTAssertNil(cards.last?.progressPercent)
    }

    @MainActor
    func testUnlimitedWithoutWindowsMakesOnlyUnlimitedCard() throws {
        let result = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "codex": {
                  "limitId": "codex",
                  "credits": { "hasCredits": false, "unlimited": true, "balance": null }
                }
              }
            }
            """)

        let cards = QuotaCardFactory.makeCards(snapshot: result.snapshot)
        XCTAssertTrue(result.snapshot.limits.isEmpty)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].valueText, "∞")
        XCTAssertEqual(cards[0].detailText, "Unlimited")
    }

    func testMissingDurationAndResetAreRetainedAndUseLimitName() throws {
        let result = try parse(
            """
            {
              "rateLimits": {
                "limitId": "codex-special",
                "limitName": "Special Usage",
                "primary": { "usedPercent": 125 }
              }
            }
            """)

        let bucket = try XCTUnwrap(result.snapshot.limits.first)
        XCTAssertNil(bucket.windowDurationMins)
        XCTAssertNil(bucket.resetsAt)
        XCTAssertEqual(bucket.label, "Special Usage")
        XCTAssertEqual(bucket.usedPercent, 100)
        XCTAssertEqual(bucket.remainingPercent, 0)
    }

    func testDuplicateWindowsAreRemoved() throws {
        let result = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "first": {
                  "limitId": "same-limit",
                  "primary": { "windowDurationMins": 300, "usedPercent": 10 }
                },
                "second": {
                  "limitId": "same-limit",
                  "primary": { "windowDurationMins": 300, "usedPercent": 20 }
                }
              }
            }
            """)

        XCTAssertEqual(result.snapshot.limits.count, 1)
    }

    func testUnlimitedNotificationRemovesPreviousLimitWindows() throws {
        let current = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "codex": {
                  "primary": { "windowDurationMins": 300, "usedPercent": 10 },
                  "secondary": { "windowDurationMins": 10080, "usedPercent": 20 }
                }
              }
            }
            """).snapshot
        let update = try parse(
            """
            {
              "rateLimitsByLimitId": {
                "codex": {
                  "credits": { "hasCredits": false, "unlimited": true, "balance": null }
                }
              }
            }
            """)

        let merged = CodexQuotaSnapshotMerger.merge(current: current, update: update)
        XCTAssertTrue(merged.limits.isEmpty)
        XCTAssertEqual(merged.credits?.unlimited, true)
    }

    func testSparsePrimaryNotificationPreservesSecondaryWindowAndMetadata() throws {
        let current = try parse(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "limitName": "Codex Usage",
                "planType": "plus",
                "primary": { "windowDurationMins": 300, "usedPercent": 10 },
                "secondary": { "windowDurationMins": 10080, "usedPercent": 20 }
              }
            }
            """).snapshot
        let update = try parse(
            """
            {
              "rateLimits": {
                "limitId": "codex",
                "primary": { "windowDurationMins": 300, "usedPercent": 35 }
              }
            }
            """)

        let merged = CodexQuotaSnapshotMerger.merge(current: current, update: update)
        XCTAssertEqual(merged.limits.map(\.label), ["5h", "1w"])
        XCTAssertEqual(merged.limits.first?.usedPercent, 35)
        XCTAssertEqual(merged.limits.last?.usedPercent, 20)
        XCTAssertEqual(merged.limits.first?.limitName, "Codex Usage")
        XCTAssertEqual(merged.planType, "plus")
    }

    func testDisplayableCreditBalanceWinsWhenStatusesAreMerged() throws {
        let result = try parse(
            """
            {
              "credits": { "hasCredits": false, "unlimited": false, "balance": "0" },
              "rateLimitsByLimitId": {
                "codex": {
                  "primary": { "windowDurationMins": 10080, "usedPercent": 10 },
                  "credits": { "hasCredits": true, "unlimited": false, "balance": "12.5" }
                }
              }
            }
            """)

        XCTAssertEqual(result.snapshot.credits?.balance, "12.5")
    }

    private func parse(_ json: String) throws -> CodexQuotaParseResult {
        try CodexQuotaParser.parse(
            data: Data(json.utf8),
            syncedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
