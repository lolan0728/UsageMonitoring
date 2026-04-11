import AppKit
import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published var fiveHourCard = QuotaCardViewData.placeholder(label: "5h", statusText: "Offline")
    @Published var weeklyCard = QuotaCardViewData.placeholder(label: "1w", statusText: "Offline")
    @Published var isQuotaLive = false
    @Published var connectionState: AppServerConnectionState = .disconnected
    @Published var connectionStatusText = "Waiting for Codex app-server"
    @Published var codexExecutablePath = "Auto detect"
    @Published var launchAtLogin = false

    private let preferences: AppPreferences
    private let snapshotStore: RateLimitSnapshotStore
    private let autostartService: AutostartService
    private let client: CodexAppServerClientMac
    private var buckets: [RateLimitBucket] = []

    init(
        preferences: AppPreferences,
        snapshotStore: RateLimitSnapshotStore,
        autostartService: AutostartService,
        client: CodexAppServerClientMac
    ) {
        self.preferences = preferences
        self.snapshotStore = snapshotStore
        self.autostartService = autostartService
        self.client = client
        self.launchAtLogin = autostartService.isEnabled() || preferences.launchAtLogin
        self.codexExecutablePath = preferences.codexExecutablePath ?? "Auto detect"
        self.client.preferredExecutablePath = preferences.codexExecutablePath

        let cachedBuckets = snapshotStore.load()
        buckets = cachedBuckets
        applyBuckets(cachedBuckets)

        client.onRateLimitsUpdated = { [weak self] buckets in
            guard let self else {
                return
            }

            self.handleRateLimitsUpdated(buckets)
        }

        client.onConnectionStateChanged = { [weak self] state in
            guard let self else {
                return
            }

            self.handleConnectionStateChanged(state)
        }
    }

    func start() async {
        await client.start()
        if let executablePath = client.executablePath {
            codexExecutablePath = executablePath
        }
    }

    func reconnect() async {
        await client.restart()
        if let executablePath = client.executablePath {
            codexExecutablePath = executablePath
        }
    }

    func refreshNow() async {
        await client.refreshRateLimits()
    }

    func locateCodexInteractively() {
        let panel = NSOpenPanel()
        panel.title = "Locate codex"
        panel.prompt = "Use This Executable"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = AppPaths.codexHome

        if panel.runModal() == .OK, let path = panel.url?.path {
            setCodexExecutablePath(path)
            Task {
                await reconnect()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        preferences.launchAtLogin = enabled
        autostartService.setEnabled(enabled)
    }

    private func setCodexExecutablePath(_ path: String) {
        guard !path.isEmpty else {
            return
        }

        codexExecutablePath = path
        preferences.codexExecutablePath = path
        client.preferredExecutablePath = path
    }

    private func handleRateLimitsUpdated(_ latestBuckets: [RateLimitBucket]) {
        guard !latestBuckets.isEmpty else {
            return
        }

        isQuotaLive = true
        buckets = latestBuckets
        snapshotStore.save(latestBuckets)
        Self.logBuckets("ui received buckets", latestBuckets)
        applyBuckets(latestBuckets)
    }

    private func handleConnectionStateChanged(_ state: AppServerConnectionState) {
        connectionState = state

        if state != .connected {
            isQuotaLive = false
        }

        if let executablePath = client.executablePath {
            codexExecutablePath = executablePath
        }

        updateConnectionStatus(for: state)
        applyConnectionStateCards(for: state)
    }

    private func applyBuckets(_ source: [RateLimitBucket]) {
        fiveHourCard = buildCard(bucket: source.first(where: { $0.windowDurationMins == 300 }), fallbackLabel: "5h")
        weeklyCard = buildCard(bucket: source.first(where: { $0.windowDurationMins == 10080 }), fallbackLabel: "1w")
        Self.log("ui cards: 5h=\(fiveHourCard.remainingText) 1w=\(weeklyCard.remainingText) live=\(isQuotaLive)")

        if isQuotaLive, let lastSyncedAtUtc = client.lastSyncedAtUtc {
            connectionStatusText = "Connected | synced \(Self.timeFormatter.string(from: lastSyncedAtUtc))"
        }
    }

    private func buildCard(bucket: RateLimitBucket?, fallbackLabel: String) -> QuotaCardViewData {
        guard let bucket else {
            return .placeholder(label: fallbackLabel, statusText: "Unavailable")
        }

        let resetText: String
        if let resetsAtUtc = bucket.resetsAtUtc {
            resetText = "Until \(Self.formatResetTime(resetsAtUtc, timeOnly: bucket.windowDurationMins == 300))"
        } else {
            resetText = "Until --"
        }

        return QuotaCardViewData(
            label: bucket.label,
            remainingText: "\(Int(bucket.remainingPercent.rounded()))%",
            resetText: resetText,
            syncedText: Self.timeFormatter.string(from: bucket.syncedAtUtc),
            statusText: "\(Int(bucket.usedPercent.rounded()))% used",
            remainingPercent: bucket.remainingPercent,
            usedPercent: bucket.usedPercent)
    }

    private func updateConnectionStatus(for state: AppServerConnectionState) {
        switch state {
        case .connected:
            connectionStatusText = "Connected to Codex app-server, syncing latest quota..."
        case .connecting:
            connectionStatusText = "Connecting to Codex app-server..."
        case .missingExecutable:
            connectionStatusText = "Codex not installed or executable not found"
        case .degraded:
            connectionStatusText = "Codex app-server unavailable, showing cached quota"
        case .disconnected:
            connectionStatusText = "Codex app-server offline, showing cached quota"
        }
    }

    private func applyConnectionStateCards(for state: AppServerConnectionState) {
        if !buckets.isEmpty {
            applyBuckets(buckets)
            return
        }

        switch state {
        case .missingExecutable:
            fiveHourCard = .placeholder(label: "5h", statusText: "Codex missing", resetText: "Locate Codex")
            weeklyCard = .placeholder(label: "1w", statusText: "Codex missing", resetText: "Locate Codex")
        case .connecting:
            fiveHourCard = .placeholder(label: "5h", statusText: "Connecting")
            weeklyCard = .placeholder(label: "1w", statusText: "Connecting")
        case .disconnected:
            fiveHourCard = .placeholder(label: "5h", statusText: "Offline", resetText: "Unavailable")
            weeklyCard = .placeholder(label: "1w", statusText: "Offline", resetText: "Unavailable")
        case .degraded:
            fiveHourCard = .placeholder(label: "5h", statusText: "Unavailable", resetText: "Unavailable")
            weeklyCard = .placeholder(label: "1w", statusText: "Unavailable", resetText: "Unavailable")
        case .connected:
            break
        }
    }

    private static func formatResetTime(_ date: Date, timeOnly: Bool) -> String {
        if timeOnly {
            return resetTimeFormatter.string(from: date)
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return resetTimeFormatter.string(from: date)
        }

        return resetDayTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let resetDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static func logBuckets(_ prefix: String, _ buckets: [RateLimitBucket]) {
        let summary = buckets
            .sorted(by: { $0.windowDurationMins < $1.windowDurationMins })
            .map { bucket in
                "\(bucket.label) used=\(Int(bucket.usedPercent.rounded())) remain=\(Int(bucket.remainingPercent.rounded()))"
            }
            .joined(separator: " | ")
        log("\(prefix): \(summary)")
    }

    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}
