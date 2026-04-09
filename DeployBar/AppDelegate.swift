import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverRootView())

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.title = " DB"
            button.font = .systemFont(ofSize: 12, weight: .semibold)
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
    }

    @objc private func applyStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = StatusIcon.current
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
