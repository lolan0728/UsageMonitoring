import AppKit

@main
enum UsageMonitoringMacApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        delegate.startApplication()
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
