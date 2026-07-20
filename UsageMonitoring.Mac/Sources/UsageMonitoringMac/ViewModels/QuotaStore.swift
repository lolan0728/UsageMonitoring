import AppKit
import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quotaCards: [QuotaCardDisplay]
    @Published private(set) var quotaSnapshot: CodexQuotaSnapshot?
    @Published var isQuotaLive = false
    @Published var connectionState: AppServerConnectionState = .disconnected
    @Published var connectionStatusText = "Waiting for Codex app-server"
    @Published var codexExecutablePath = "Auto detect"
    @Published var launchAtLogin = false

    private let preferences: AppPreferences
    private let snapshotStore: RateLimitSnapshotStore
    private let autostartService: AutostartService
    private let client: CodexAppServerClientMac

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
        launchAtLogin = autostartService.isEnabled() || preferences.launchAtLogin
        codexExecutablePath = preferences.codexExecutablePath ?? "Auto detect"
        client.preferredExecutablePath = preferences.codexExecutablePath

        let cachedSnapshot = snapshotStore.load()
        quotaSnapshot = cachedSnapshot
        quotaCards = QuotaCardFactory.makeCards(snapshot: cachedSnapshot)

        client.onQuotaSnapshotUpdated = { [weak self] snapshot in
            self?.handleQuotaSnapshotUpdated(snapshot)
        }

        client.onConnectionStateChanged = { [weak self] state in
            self?.handleConnectionStateChanged(state)
        }
    }

    func start() async {
        await client.start()
        if let executablePath = client.executablePath {
            codexExecutablePath = executablePath
        }
    }

    func reconnect() async {
        isQuotaLive = false
        refreshCards()
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

    func handleQuotaSnapshotUpdated(_ snapshot: CodexQuotaSnapshot) {
        guard snapshot.hasDisplayableUsage else {
            return
        }

        quotaSnapshot = snapshot
        isQuotaLive = true
        snapshotStore.save(snapshot)
        refreshCards()
        connectionStatusText = "Connected | synced \(Self.timeFormatter.string(from: snapshot.syncedAt))"
        Self.logSnapshot("ui received snapshot", snapshot)
    }

    func handleConnectionStateChanged(_ state: AppServerConnectionState) {
        connectionState = state

        if state != .connected {
            isQuotaLive = false
        }

        if let executablePath = client.executablePath {
            codexExecutablePath = executablePath
        }

        updateConnectionStatus(for: state)
        refreshCards()
    }

    private func setCodexExecutablePath(_ path: String) {
        guard !path.isEmpty else {
            return
        }

        codexExecutablePath = path
        preferences.codexExecutablePath = path
        client.preferredExecutablePath = path
    }

    private func refreshCards() {
        quotaCards = QuotaCardFactory.makeCards(snapshot: quotaSnapshot)
        let summary = quotaCards.map { "\($0.label)=\($0.valueText)" }.joined(separator: " | ")
        Self.log("ui cards: \(summary) live=\(isQuotaLive)")
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func logSnapshot(_ prefix: String, _ snapshot: CodexQuotaSnapshot) {
        let limits = snapshot.limits
            .map { "\($0.label) used=\(Int($0.usedPercent.rounded())) remain=\(Int($0.remainingPercent.rounded()))" }
            .joined(separator: " | ")
        let limitSummary = limits.isEmpty ? "<no limits>" : limits
        let creditBalance = snapshot.credits?.balance ?? "nil"
        log("\(prefix): \(limitSummary) credits=\(creditBalance)")
    }

    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}
