import Foundation

final class RateLimitSnapshotStore {
    private struct SnapshotDocument: Codable {
        let savedAtUtc: Date
        let buckets: [RateLimitBucket]
    }

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

    func load() -> [RateLimitBucket] {
        ensureDirectoryExists()

        guard let data = try? Data(contentsOf: AppPaths.rateLimitSnapshotURL),
              let document = try? decoder.decode(SnapshotDocument.self, from: data)
        else {
            return []
        }

        return document.buckets.sorted(by: { $0.windowDurationMins < $1.windowDurationMins })
    }

    func save(_ buckets: [RateLimitBucket]) {
        guard !buckets.isEmpty else {
            return
        }

        ensureDirectoryExists()
        let document = SnapshotDocument(savedAtUtc: Date(), buckets: buckets.sorted(by: { $0.windowDurationMins < $1.windowDurationMins }))

        guard let data = try? encoder.encode(document) else {
            return
        }

        try? data.write(to: AppPaths.rateLimitSnapshotURL, options: .atomic)
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: AppPaths.appSupportDirectory, withIntermediateDirectories: true)
    }
}
