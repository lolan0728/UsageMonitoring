import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum MenuIcons {
    static let clickThroughEnabledSystemName = "checkmark"
    static let clickThroughDisabledSystemName = "circle"
    static let hideSystemName = "eye.slash"
    static let quitSystemName = "xmark.square"

#if canImport(AppKit)
    static func clickThroughImage(enabled: Bool) -> NSImage {
        symbolImage(
            named: enabled ? clickThroughEnabledSystemName : clickThroughDisabledSystemName,
            weight: enabled ? .semibold : .regular,
            accessibilityDescription: enabled ? "Click through enabled" : "Click through disabled")
    }

    static var hideImage: NSImage {
        symbolImage(named: hideSystemName, weight: .regular, accessibilityDescription: "Hide")
    }

    static var quitImage: NSImage {
        symbolImage(named: quitSystemName, weight: .regular, accessibilityDescription: "Quit")
    }

    private static func symbolImage(
        named symbolName: String,
        weight: NSFont.Weight,
        accessibilityDescription: String
    ) -> NSImage {
        let iconSize = NSSize(width: 14, height: 14)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: weight)

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        {
            symbol.isTemplate = true
            return symbol
        }

        let placeholder = NSImage(size: iconSize)
        placeholder.isTemplate = true
        return placeholder
    }
#endif
}
