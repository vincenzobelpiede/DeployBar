import AppKit
import SwiftUI

enum StatusIconState {
    case idle, deploying, failed
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var iconState: StatusIconState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable Launch at Login by default on first run only.
        let firstRunKey = "launchAtLoginFirstRunDone"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            LaunchAtLogin.isEnabled = true
            UserDefaults.standard.set(true, forKey: firstRunKey)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 700)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverRootView())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        applyStatusIcon()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyStatusIcon),
            name: StatusIcon.changedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DeployBar.iconStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let raw = note.userInfo?["state"] as? String {
                switch raw {
                case "deploying": self?.iconState = .deploying
                case "failed": self?.iconState = .failed
                default: self?.iconState = .idle
                }
                self?.applyStatusIcon()
            }
        }
    }

    @objc private func applyStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name: String
        switch iconState {
        case .idle: name = StatusIcon.current
        case .deploying: name = "arrow.2.circlepath"
        case .failed: name = "xmark.circle.fill"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "DeployBar")
        img?.isTemplate = true
        button.image = img
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
