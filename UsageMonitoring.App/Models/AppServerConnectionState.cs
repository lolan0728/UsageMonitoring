namespace UsageMonitoring.App.Models;

public enum AppServerConnectionState
{
    Disconnected,
    Connecting,
    MissingExecutable,
    Connected,
    Degraded
}
