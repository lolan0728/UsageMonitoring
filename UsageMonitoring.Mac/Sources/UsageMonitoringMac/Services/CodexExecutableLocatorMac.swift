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
        var candidates: [String?] = [
            preferredPath,
            AppPaths.codexHome.appendingPathComponent(".sandbox-bin/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        candidates.append(contentsOf: pathEntries.map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex").path })
        return candidates
    }
}
