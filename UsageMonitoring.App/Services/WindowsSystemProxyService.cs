using Microsoft.Win32;

namespace UsageMonitoring.App.Services;

public sealed class WindowsSystemProxyService
{
    private const string InternetSettingsKey = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

    public ProxyEnvironment GetProxyEnvironment()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(InternetSettingsKey);
            if (key is null)
            {
                return ProxyEnvironment.Disabled;
            }

            var proxyEnabled = (key.GetValue("ProxyEnable") as int?) == 1;
            var proxyServer = key.GetValue("ProxyServer") as string;
            if (!proxyEnabled || string.IsNullOrWhiteSpace(proxyServer))
            {
                return ProxyEnvironment.Disabled;
            }

            var entries = ParseProxyEntries(proxyServer);
            if (entries.Count == 0)
            {
                return ProxyEnvironment.Disabled;
            }

            entries.TryGetValue("http", out var httpProxy);
            entries.TryGetValue("https", out var httpsProxy);
            entries.TryGetValue("socks", out var socksProxy);
            entries.TryGetValue("*", out var sharedProxy);

            httpProxy ??= sharedProxy;
            httpsProxy ??= sharedProxy ?? httpProxy;
            var allProxy = socksProxy ?? httpsProxy ?? httpProxy;

            if (httpProxy is null && httpsProxy is null && allProxy is null)
            {
                return ProxyEnvironment.Disabled;
            }

            return new ProxyEnvironment(httpProxy, httpsProxy, allProxy);
        }
        catch
        {
            return ProxyEnvironment.Disabled;
        }
    }

    private static Dictionary<string, string> ParseProxyEntries(string proxyServer)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var segments = proxyServer.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var segment in segments)
        {
            if (segment.Contains('='))
            {
                var parts = segment.Split('=', 2, StringSplitOptions.TrimEntries);
                if (parts.Length != 2 || string.IsNullOrWhiteSpace(parts[1]))
                {
                    continue;
                }

                result[parts[0]] = NormalizeProxyUri(parts[0], parts[1]);
            }
            else if (!string.IsNullOrWhiteSpace(segment))
            {
                result["*"] = NormalizeProxyUri("http", segment);
            }
        }

        return result;
    }

    private static string NormalizeProxyUri(string schemeHint, string value)
    {
        if (value.Contains("://", StringComparison.Ordinal))
        {
            return value;
        }

        return schemeHint.Equals("socks", StringComparison.OrdinalIgnoreCase)
            ? $"socks5://{value}"
            : $"http://{value}";
    }
}

public sealed record ProxyEnvironment(string? HttpProxy, string? HttpsProxy, string? AllProxy)
{
    public static ProxyEnvironment Disabled { get; } = new(null, null, null);

    public bool IsEnabled =>
        !string.IsNullOrWhiteSpace(HttpProxy) ||
        !string.IsNullOrWhiteSpace(HttpsProxy) ||
        !string.IsNullOrWhiteSpace(AllProxy);
}
