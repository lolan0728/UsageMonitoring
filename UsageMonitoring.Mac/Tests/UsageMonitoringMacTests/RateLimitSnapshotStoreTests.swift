import Foundation
import XCTest
@testable import UsageMonitoringMac

final class RateLimitSnapshotStoreTests: XCTestCase {
    func testNewSnapshotRoundTripsAllFields() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let snapshot = makeSnapshot()

        fixture.store.save(snapshot)
        let loaded = try XCTUnwrap(fixture.store.load())

        XCTAssertEqual(loaded, snapshot)
    }

    func testLegacySnapshotDocumentMigrates() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let legacy =
            """
            {
              "savedAtUtc": "2027-01-15T08:00:00Z",
              "buckets": [
                {
                  "label": "5h",
                  "windowDurationMins": 300,
                  "usedPercent": 25,
                  "remainingPercent": 75,
                  "resetsAtUtc": "2027-01-15T10:00:00Z",
                  "syncedAtUtc": "2027-01-15T08:00:00Z",
                  "limitId": "legacy",
                  "limitName": "Legacy"
                }
              ]
            }
            """
        try Data(legacy.utf8).write(to: fixture.url)

        let migrated = try XCTUnwrap(fixture.store.load())
        XCTAssertEqual(migrated.limits.count, 1)
        XCTAssertEqual(migrated.limits[0].label, "5h")
        XCTAssertNil(migrated.credits)
        XCTAssertNil(migrated.planType)
    }

    func testEmptySnapshotDoesNotOverwriteLastValidCache() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let snapshot = makeSnapshot()
        fixture.store.save(snapshot)

        fixture.store.save(CodexQuotaSnapshot(limits: [], credits: nil, planType: nil, syncedAt: Date()))

        XCTAssertEqual(fixture.store.load(), snapshot)
    }

    @MainActor
    func testOfflineCacheStartsDimmedAndFreshSnapshotBecomesLive() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cached = makeSnapshot()
        fixture.store.save(cached)
        let suiteName = "UsageMonitoringMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let client = CodexAppServerClientMac(locator: CodexExecutableLocatorMac())
        let store = QuotaStore(
            preferences: preferences,
            snapshotStore: fixture.store,
            autostartService: AutostartService(),
            client: client)

        XCTAssertFalse(store.isQuotaLive)
        XCTAssertEqual(store.quotaCards.map(\.label), ["1w"])

        let fresh = CodexQuotaSnapshot(
            limits: cached.limits,
            credits: CreditStatus(hasCredits: true, unlimited: false, balance: "8"),
            planType: "pro",
            syncedAt: Date(timeIntervalSince1970: 1_800_000_060))
        store.handleQuotaSnapshotUpdated(fresh)

        XCTAssertTrue(store.isQuotaLive)
        XCTAssertEqual(store.quotaCards.map(\.label), ["1w", "Credits"])
    }

    private func makeFixture() throws -> (directory: URL, url: URL, store: RateLimitSnapshotStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageMonitoringMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rate-limits.json")
        return (directory, url, RateLimitSnapshotStore(snapshotURL: url))
    }

    private func makeSnapshot() -> CodexQuotaSnapshot {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return CodexQuotaSnapshot(
            limits: [
                RateLimitBucket(
                    id: "codex|primary|10080",
                    label: "1w",
                    windowDurationMins: 10080,
                    usedPercent: 20,
                    remainingPercent: 80,
                    resetsAt: Date(timeIntervalSince1970: 1_900_000_000),
                    syncedAt: syncedAt,
                    limitId: "codex",
                    limitName: "Codex",
                    windowRole: "primary")
            ],
            credits: CreditStatus(hasCredits: false, unlimited: false, balance: "0"),
            planType: "plus",
            syncedAt: syncedAt)
    }
}
