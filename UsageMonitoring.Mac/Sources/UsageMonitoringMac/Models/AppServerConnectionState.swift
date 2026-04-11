enum AppServerConnectionState: String, Codable {
    case disconnected
    case connecting
    case missingExecutable
    case connected
    case degraded
}
