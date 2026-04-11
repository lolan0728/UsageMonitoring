// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageMonitoring.Mac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "UsageMonitoringMac",
            targets: ["UsageMonitoringMac"])
    ],
    targets: [
        .executableTarget(
            name: "UsageMonitoringMac",
            path: "Sources/UsageMonitoringMac")
    ]
)
