import Foundation

enum AppPaths {
    static let codexHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent(".codex", isDirectory: true)

    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return base.appendingPathComponent("Usage Monitoring", isDirectory: true)
    }()

    static let rateLimitSnapshotURL = appSupportDirectory.appendingPathComponent("rate-limits.json")
}
