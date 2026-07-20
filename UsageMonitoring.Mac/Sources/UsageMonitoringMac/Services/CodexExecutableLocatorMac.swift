import Foundation

final class CodexExecutableLocatorMac {
    func locate(preferredPath: String? = nil) -> String? {
        for candidate in enumerateCandidates(preferredPath: preferredPath) {
            guard let candidate, !candidate.isEmpty else {
                continue
            }

            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func enumerateCandidates(preferredPath: String?) -> [String?] {
        var candidates: [String?] = [preferredPath]
        candidates.append(contentsOf: Self.standardCandidatePaths())

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        candidates.append(contentsOf: pathEntries.map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex").path })
        candidates.append(resolveFromLoginShell())
        return candidates
    }

    static func standardCandidatePaths(
        codexHome: URL = AppPaths.codexHome,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [String] {
        [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            codexHome.appendingPathComponent("plugins/.plugin-appserver/codex").path,
            codexHome.appendingPathComponent(".sandbox-bin/codex").path,
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
    }

    private func resolveFromLoginShell() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else {
            return nil
        }

        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v codex"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return nil
        }

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) })
    }
}
