# UsageMonitoring.Mac

Native macOS implementation of Usage Monitoring built with SwiftUI and AppKit.

## Current Status

- SwiftPM-based macOS app target
- Menu bar extra with `Show Window` / `Hide Window`
- Floating window with remembered position
- Dynamic quota capsules for every app-server limit window
- Credits and Unlimited states without fabricated percentage progress
- Cached snapshot loading on launch
- Dimmed vs live state switching
- Codex executable discovery on macOS
- `codex app-server --analytics-default-enabled` JSON-RPC client
- `initialize`
- `initialized`
- `account/rateLimits/read`
- `account/rateLimits/updated`
- New `rateLimitsByLimitId` payloads with legacy `rateLimits` fallback
- 60-second fallback polling
- Manual `Locate Codex`
- Launch at login toggle

## Open In Xcode

1. Open Xcode.
2. Choose `File` -> `Open...`
3. Select `/Users/lolan/文档/Usage Monitoring/UsageMonitoring.Mac/Package.swift`
4. Run the `UsageMonitoringMac` product target.

Xcode can open the Swift package directly, so a separate `.xcodeproj` is not required for now.

## Run From Terminal

```bash
cd "/Users/lolan/文档/Usage Monitoring/UsageMonitoring.Mac"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run UsageMonitoringMac
```

## Tests

```bash
cd "/Users/lolan/文档/Usage Monitoring/UsageMonitoring.Mac"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Data Sources

- Preferred executable path from app preferences
- `/Applications/ChatGPT.app/Contents/Resources/codex`
- `/Applications/Codex.app/Contents/Resources/codex`
- `~/.codex/plugins/.plugin-appserver/codex`
- `~/.codex/.sandbox-bin/codex`
- `/opt/homebrew/bin/codex` and `/usr/local/bin/codex`
- `codex` from `PATH` or the user's login shell

## Persistence

- Snapshot path:
  `/Users/<you>/Library/Application Support/Usage Monitoring/rate-limits.json`
- Window position and preferred executable path are stored in `UserDefaults`

## Behavior Notes

- Cached quota can render immediately on startup, but the UI stays dimmed
  until the current app session receives fresh quota data.
- If Codex is unavailable, cached data remains visible when present.
- If no cache or displayable usage exists, a dimmed `Usage unavailable`
  capsule is shown.
- The panel height follows the number of visible capsules while preserving the
  nearest vertical screen edge.
