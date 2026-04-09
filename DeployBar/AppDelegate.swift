import AppKit
import SwiftUI

enum StatusIconState {
    case idle, deploying, failed
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var iconState: StatusIconState = .idle
    let deployEngine = DeployEngine()
    private var clickWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Eager-init Sparkle so its scheduled background checks start running.
        _ = UpdaterController.shared.controller

        // Enable Launch at Login by default on first run only.
        let firstRunKey = "launchAtLoginFirstRunDone"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            LaunchAtLogin.isEnabled = true
            UserDefaults.standard.set(true, forKey: firstRunKey)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 700)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView().environmentObject(deployEngine)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.action = #selector(handleStatusClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
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
        let img: NSImage?
        switch iconState {
        case .idle:
            let name = StatusIcon.current
            if name == StatusIcon.customAssetId {
                img = NSImage(named: StatusIcon.customAssetName)
            } else {
                img = NSImage(systemSymbolName: name, accessibilityDescription: "DeployBar")
            }
        case .deploying:
            img = NSImage(systemSymbolName: "arrow.2.circlepath", accessibilityDescription: "Deploying")
        case .failed:
            img = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Failed")
        }
        img?.isTemplate = true
        button.image = img
    }

    @objc private func handleStatusClick(_ sender: AnyObject?) {
        // Distinguish single click vs double click manually using NSEvent.
        let clickCount = NSApp.currentEvent?.clickCount ?? 1
        if clickCount >= 2 {
            // Cancel the pending single-click action and open the detached window.
            clickWorkItem?.cancel()
            clickWorkItem = nil
            DeployStatusWindowController.shared.show(engine: deployEngine)
            return
        }
        // Defer the popover toggle briefly so a follow-up click can upgrade
        // the gesture to a double click.
        clickWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.togglePopover(sender)
        }
        clickWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
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
