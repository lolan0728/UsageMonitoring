import Foundation
import SystemConfiguration

final class CodexAppServerClientMac: @unchecked Sendable {
    private struct PendingResponse {
        let semaphore: DispatchSemaphore
        var result: Result<[String: Any], Error>?
    }

    private enum ClientError: Error {
        case processUnavailable
        case invalidResponse
        case timeout
    }

    private let locator: CodexExecutableLocatorMac
    private let rpcQueue = DispatchQueue(label: "UsageMonitoringMac.CodexRPC")
    private let stateLock = NSLock()
    private static let diagnosticsLock = NSLock()

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pollTimer: DispatchSourceTimer?
    private var pending: [Int64: PendingResponse] = [:]
    private var requestId: Int64 = 0
    private var _connectionState: AppServerConnectionState = .disconnected
    private var _executablePath: String?
    private var _preferredExecutablePath: String?
    private var _lastSyncedAtUtc: Date?
    private var _latestSnapshot: CodexQuotaSnapshot?

    var onQuotaSnapshotUpdated: (@MainActor (CodexQuotaSnapshot) -> Void)?
    var onConnectionStateChanged: (@MainActor (AppServerConnectionState) -> Void)?

    init(locator: CodexExecutableLocatorMac, preferredExecutablePath: String? = nil) {
        self.locator = locator
        self._preferredExecutablePath = preferredExecutablePath
    }

    var executablePath: String? {
        stateLock.withLock { _executablePath }
    }

    var preferredExecutablePath: String? {
        get { stateLock.withLock { _preferredExecutablePath } }
        set { stateLock.withLock { _preferredExecutablePath = newValue } }
    }

    var lastSyncedAtUtc: Date? {
        stateLock.withLock { _lastSyncedAtUtc }
    }

    func start() async {
        await withCheckedContinuation { continuation in
            rpcQueue.async { [self] in
                startSync()
                continuation.resume()
            }
        }
    }

    func restart() async {
        await withCheckedContinuation { continuation in
            rpcQueue.async { [self] in
                stopSync()
                startSync()
                continuation.resume()
            }
        }
    }

    func refreshRateLimits() async {
        await withCheckedContinuation { continuation in
            rpcQueue.async { [self] in
                refreshRateLimitsSync()
                continuation.resume()
            }
        }
    }

    deinit {
        stopSync()
    }

    private func startSync() {
        if let process, process.isRunning {
            return
        }

        updateConnectionState(.connecting)

        let resolvedExecutable = locator.locate(preferredPath: preferredExecutablePath)
        stateLock.withLock {
            _executablePath = resolvedExecutable
        }

        Self.log("resolved codex executable: \(resolvedExecutable ?? "<missing>")")

        guard let resolvedExecutable else {
            updateConnectionState(.missingExecutable)
            return
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = Process()
        let environment = Self.buildProcessEnvironment()

        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = ["app-server", "--analytics-default-enabled"]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            self?.handleProcessExit(terminatedProcess)
        }

        if let version = Self.codexVersion(executablePath: resolvedExecutable, environment: environment) {
            Self.log("codex version: \(version)")
        } else {
            Self.log("codex version: <unavailable>")
        }
        Self.log("proxy environment: \(Self.proxySummary(from: environment))")

        installReadHandlers(stdout: stdoutPipe.fileHandleForReading, stderr: stderrPipe.fileHandleForReading)

        do {
            try process.run()
        } catch {
            updateConnectionState(.degraded)
            clearHandles()
            return
        }

        stateLock.withLock {
            self.process = process
            stdinHandle = stdinPipe.fileHandleForWriting
            stdoutHandle = stdoutPipe.fileHandleForReading
            stderrHandle = stderrPipe.fileHandleForReading
        }

        do {
            try initializeSync()
            refreshRateLimitsSync()
            startPollTimer()
        } catch {
            Self.log("failed during startSync: \(error)")
            updateConnectionState(.degraded)
        }
    }

    private func stopSync() {
        pollTimer?.cancel()
        pollTimer = nil

        let currentProcess = stateLock.withLock { process }
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        if let currentProcess, currentProcess.isRunning {
            currentProcess.terminate()
        }

        stateLock.withLock {
            process = nil
            stdinHandle = nil
            stdoutHandle = nil
            stderrHandle = nil
            stdoutBuffer.removeAll(keepingCapacity: false)
            stderrBuffer.removeAll(keepingCapacity: false)
            for (_, entry) in pending {
                entry.semaphore.signal()
            }
            pending.removeAll()
        }
    }

    private func initializeSync() throws {
        _ = try sendRequestSync(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "UsageMonitoring",
                    "title": "Usage Monitoring",
                    "version": "0.1.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ])

        try sendNotificationSync(method: "initialized", params: [:])

        updateConnectionState(.connected)
    }

    private func refreshRateLimitsSync() {
        Self.log("sending request: account/rateLimits/read")
        guard let result = try? sendRequestSync(method: "account/rateLimits/read", params: nil),
              let parsed = try? Self.parseQuotaPayload(result)
        else {
            Self.log("rate limit read failed; keeping cached snapshot if present")
            updateConnectionState(.degraded)
            return
        }

        guard parsed.snapshot.hasDisplayableUsage else {
            Self.log("rate limit read returned no displayable usage; keeping the last valid snapshot")
            return
        }

        Self.logSnapshot("parsed account/rateLimits/read", snapshot: parsed.snapshot)
        publishQuotaSnapshot(parsed.snapshot)
    }

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: rpcQueue)
        timer.schedule(deadline: .now() + .seconds(60), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in
            self?.refreshRateLimitsSync()
        }
        timer.resume()
        pollTimer = timer
    }

    private func installReadHandlers(stdout: FileHandle, stderr: FileHandle) {
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            self?.consumeStreamData(data, isErrorStream: false)
        }

        stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            self?.consumeStreamData(data, isErrorStream: true)
        }
    }

    private func consumeStreamData(_ data: Data, isErrorStream: Bool) {
        let lines = stateLock.withLock { () -> [String] in
            var buffer = isErrorStream ? stderrBuffer : stdoutBuffer
            buffer.append(data)

            var completedLines: [String] = []
            while let range = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    completedLines.append(line)
                }
                buffer.removeSubrange(0...range.lowerBound)
            }

            if isErrorStream {
                stderrBuffer = buffer
            } else {
                stdoutBuffer = buffer
            }

            return completedLines
        }

        guard !isErrorStream else {
            for line in lines {
                Self.log("[app-server stderr] \(line)")
            }
            return
        }

        for line in lines {
            Self.log("[raw rpc] \(line)")
            handleIncomingLine(line)
        }
    }

    private func handleIncomingLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if let rawId = payload["id"] as? NSNumber {
            let responseId = rawId.int64Value
            if let result = payload["result"] as? [String: Any] {
                resolvePending(id: responseId, result: .success(result))
                return
            }

            if let error = payload["error"] as? [String: Any] {
                resolvePending(id: responseId, result: .failure(NSError(domain: "CodexAppServer", code: 1, userInfo: error)))
                return
            }
        }

        guard let method = payload["method"] as? String else {
            return
        }

        if method == "account/rateLimits/updated",
           let params = payload["params"] as? [String: Any],
           let parsed = try? Self.parseQuotaPayload(params) {
            let snapshot = mergeNotification(parsed)
            guard snapshot.hasDisplayableUsage else {
                Self.log("rate limit notification returned no displayable usage; keeping the last valid snapshot")
                return
            }

            Self.logSnapshot("parsed account/rateLimits/updated", snapshot: snapshot)
            publishQuotaSnapshot(snapshot)
        }
    }

    private func publishQuotaSnapshot(_ snapshot: CodexQuotaSnapshot) {
        stateLock.withLock {
            _latestSnapshot = snapshot
            _lastSyncedAtUtc = snapshot.syncedAt
        }

        updateConnectionState(.connected)
        Self.logSnapshot("publishing snapshot", snapshot: snapshot)
        let callback = onQuotaSnapshotUpdated
        Task { @MainActor in
            callback?(snapshot)
        }
    }

    private func mergeNotification(_ update: CodexQuotaParseResult) -> CodexQuotaSnapshot {
        CodexQuotaSnapshotMerger.merge(
            current: stateLock.withLock { _latestSnapshot },
            update: update)
    }

    private func sendRequestSync(method: String, params: [String: Any]?) throws -> [String: Any] {
        guard let stdinHandle = stateLock.withLock({ stdinHandle }),
              let process = stateLock.withLock({ process }),
              process.isRunning
        else {
            throw ClientError.processUnavailable
        }

        let nextId = stateLock.withLock { () -> Int64 in
            requestId += 1
            return requestId
        }

        let semaphore = DispatchSemaphore(value: 0)
        stateLock.withLock {
            pending[nextId] = PendingResponse(semaphore: semaphore, result: nil)
        }

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId,
            "method": method
        ]

        if let params {
            payload["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        Self.log("[rpc request] \(String(decoding: data, as: UTF8.self))")
        try stdinHandle.write(contentsOf: data)
        try stdinHandle.write(contentsOf: Data([0x0A]))

        guard semaphore.wait(timeout: .now() + 15) == .success else {
            _ = stateLock.withLock {
                pending.removeValue(forKey: nextId)
            }
            throw ClientError.timeout
        }

        guard let response = stateLock.withLock({ pending.removeValue(forKey: nextId)?.result }) else {
            throw ClientError.invalidResponse
        }

        return try response.get()
    }

    private func sendNotificationSync(method: String, params: [String: Any]?) throws {
        guard let stdinHandle = stateLock.withLock({ stdinHandle }),
              let process = stateLock.withLock({ process }),
              process.isRunning
        else {
            throw ClientError.processUnavailable
        }

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            payload["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        Self.log("[rpc notification] \(String(decoding: data, as: UTF8.self))")
        try stdinHandle.write(contentsOf: data)
        try stdinHandle.write(contentsOf: Data([0x0A]))
    }

    private func resolvePending(id: Int64, result: Result<[String: Any], Error>) {
        var semaphore: DispatchSemaphore?
        stateLock.withLock {
            guard var pendingResponse = pending[id] else {
                return
            }

            pendingResponse.result = result
            pending[id] = pendingResponse
            semaphore = pendingResponse.semaphore
        }

        semaphore?.signal()
    }

    private func handleProcessExit(_ terminatedProcess: Process) {
        let handled = stateLock.withLock { () -> Bool in
            guard process === terminatedProcess else {
                return false
            }

            for (_, entry) in pending {
                entry.semaphore.signal()
            }
            pending.removeAll()
            process = nil
            stdinHandle = nil
            stdoutHandle = nil
            stderrHandle = nil
            return true
        }

        guard handled else {
            return
        }
        updateConnectionState(lastSyncedAtUtc == nil ? .disconnected : .degraded)
    }

    private func clearHandles() {
        stateLock.withLock {
            process = nil
            stdinHandle = nil
            stdoutHandle = nil
            stderrHandle = nil
        }
    }

    private func updateConnectionState(_ newState: AppServerConnectionState) {
        let changed = stateLock.withLock { () -> Bool in
            guard _connectionState != newState else {
                return false
            }

            _connectionState = newState
            return true
        }

        guard changed else {
            return
        }

        let callback = onConnectionStateChanged
        Task { @MainActor in
            callback?(newState)
        }
    }

    private static func parseQuotaPayload(_ payload: [String: Any]) throws -> CodexQuotaParseResult {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try CodexQuotaParser.parse(data: data)
    }

    private static func sortBuckets(_ buckets: [RateLimitBucket]) -> [RateLimitBucket] {
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

    private static func buildProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let proxyKeys = [
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "NO_PROXY",
            "no_proxy"
        ]

        let alreadyHasProxy = proxyKeys.contains { key in
            guard let value = environment[key] else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if alreadyHasProxy {
            return environment
        }

        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return environment
        }

        func stringValue(_ key: String) -> String? {
            (settings[key] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func intValue(_ key: String) -> Int? {
            switch settings[key] {
            case let value as Int:
                return value
            case let value as NSNumber:
                return value.intValue
            default:
                return nil
            }
        }

        func boolValue(_ key: String) -> Bool {
            switch settings[key] {
            case let value as Int:
                return value != 0
            case let value as NSNumber:
                return value.intValue != 0
            default:
                return false
            }
        }

        func assign(_ keys: [String], value: String?) {
            guard let value, !value.isEmpty else {
                return
            }

            for key in keys {
                environment[key] = value
            }
        }

        if boolValue(kSCPropNetProxiesHTTPEnable as String),
           let host = stringValue(kSCPropNetProxiesHTTPProxy as String),
           let port = intValue(kSCPropNetProxiesHTTPPort as String) {
            assign(["HTTP_PROXY", "http_proxy"], value: "http://\(host):\(port)")
        }

        if boolValue(kSCPropNetProxiesHTTPSEnable as String),
           let host = stringValue(kSCPropNetProxiesHTTPSProxy as String),
           let port = intValue(kSCPropNetProxiesHTTPSPort as String) {
            assign(["HTTPS_PROXY", "https_proxy"], value: "http://\(host):\(port)")
        }

        if boolValue(kSCPropNetProxiesSOCKSEnable as String),
           let host = stringValue(kSCPropNetProxiesSOCKSProxy as String),
           let port = intValue(kSCPropNetProxiesSOCKSPort as String) {
            assign(["ALL_PROXY", "all_proxy"], value: "socks5://\(host):\(port)")
        }

        if let excludes = settings[kSCPropNetProxiesExceptionsList as String] as? [String],
           !excludes.isEmpty {
            let noProxy = excludes.joined(separator: ",")
            assign(["NO_PROXY", "no_proxy"], value: noProxy)
        }

        return environment
    }

    private static func codexVersion(executablePath: String, environment: [String: String]) -> String? {
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]
        process.environment = environment
        process.terminationHandler = { _ in
            finished.signal()
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        guard finished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            return nil
        }

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let combined = [stdout, stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return combined.isEmpty ? nil : combined
    }

    private static func proxySummary(from environment: [String: String]) -> String {
        [
            "HTTP_PROXY=\(environment["HTTP_PROXY"] ?? environment["http_proxy"] ?? "<unset>")",
            "HTTPS_PROXY=\(environment["HTTPS_PROXY"] ?? environment["https_proxy"] ?? "<unset>")",
            "ALL_PROXY=\(environment["ALL_PROXY"] ?? environment["all_proxy"] ?? "<unset>")",
            "NO_PROXY=\(environment["NO_PROXY"] ?? environment["no_proxy"] ?? "<unset>")"
        ].joined(separator: " | ")
    }

    private static func logSnapshot(_ prefix: String, snapshot: CodexQuotaSnapshot) {
        let limits = sortBuckets(snapshot.limits)
            .map { bucket in
                let window = bucket.windowDurationMins.map(String.init) ?? "nil"
                return "\(bucket.label) used=\(Int(bucket.usedPercent.rounded())) remain=\(Int(bucket.remainingPercent.rounded())) window=\(window)"
            }
            .joined(separator: " | ")
        let credits: String
        if let status = snapshot.credits {
            let balance = status.balance ?? "nil"
            credits = "credits(has=\(status.hasCredits), unlimited=\(status.unlimited), balance=\(balance))"
        } else {
            credits = "credits=nil"
        }
        let limitSummary = limits.isEmpty ? "<no limits>" : limits
        let planType = snapshot.planType ?? "nil"
        log("\(prefix): \(limitSummary) | \(credits) | plan=\(planType)")
    }

    private static func log(_ message: String) {
        diagnosticsLock.withLock {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)"
            print(line)

            try? FileManager.default.createDirectory(at: AppPaths.appSupportDirectory, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)

            if FileManager.default.fileExists(atPath: AppPaths.appSupportDirectory.appendingPathComponent("app-server-diagnostics.log").path) {
                if let handle = try? FileHandle(forWritingTo: AppPaths.appSupportDirectory.appendingPathComponent("app-server-diagnostics.log")) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    return
                }
            }

            try? data.write(to: AppPaths.appSupportDirectory.appendingPathComponent("app-server-diagnostics.log"), options: .atomic)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}
