import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = buildWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func buildWindow() -> NSWindow {
        let size = NSSize(width: 360, height: 220)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "About UsageMonitoringMac"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.center()

        let contentView = AboutContentView(
            frame: NSRect(origin: .zero, size: size),
            iconImage: Self.makeAboutIcon(),
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Usage Monitoring",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            githubURL: URL(string: "https://github.com/lolan0728/UsageMonitoring")!
        )
        window.contentView = contentView
        contentView.layoutSubtreeIfNeeded()
        window.setContentSize(contentView.fittingSize)
        return window
    }

    private static func makeAboutIcon() -> NSImage {
        // Prefer a real app bundle icon when available; fall back to rendering our existing icon view.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
        }

        let iconSize: CGFloat = 128
        let view = ScalableDoubleRingIconView(isLive: true)
            .frame(width: iconSize, height: iconSize)
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: iconSize + 24, height: iconSize + 24)

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

@MainActor
private final class AboutContentView: NSView {
    private let githubURL: URL

    init(frame frameRect: NSRect, iconImage: NSImage, appName: String, version: String, build: String, githubURL: URL) {
        self.githubURL = githubURL
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let iconView = NSImageView()
        iconView.image = iconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = Self.makeLabel(appName, size: 20, weight: .bold, color: .labelColor)
        let versionLabel = Self.makeLabel("Version \(version) (\(build))", size: 13, weight: .medium, color: .secondaryLabelColor)
        let authorLabel = Self.makeLabel("Author: lolan Eos", size: 13, weight: .medium, color: .secondaryLabelColor)

        let repoCaption = Self.makeLabel("GitHub Repository", size: 12, weight: .semibold, color: .secondaryLabelColor)

        let linkButton = NSButton(title: githubURL.absoluteString, target: self, action: #selector(openGitHub))
        linkButton.isBordered = false
        linkButton.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        linkButton.contentTintColor = NSColor.linkColor
        linkButton.lineBreakMode = .byTruncatingMiddle
        linkButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel, versionLabel, authorLabel, repoCaption, linkButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 128),
            iconView.heightAnchor.constraint(equalToConstant: 128),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),

            linkButton.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(githubURL)
    }

    private static func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
