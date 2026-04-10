import SwiftUI
import AppKit

/// A standalone floating window that mirrors the current deploy state.
/// Opened via double-click on the menu bar icon. Stays visible until the
/// user manually closes it.
final class DeployStatusWindowController: NSWindowController {
    static let shared = DeployStatusWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeployBar — Status"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(engine: DeployEngine) {
        if window?.contentViewController == nil {
            window?.contentViewController = NSHostingController(
                rootView: DeployStatusView().environmentObject(engine)
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DeployStatusView: View {
    @EnvironmentObject var deployEngine: DeployEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: deployEngine.isDeploying ? "arrow.2.circlepath" : "checkmark.circle.fill")
                    .foregroundStyle(deployEngine.isDeploying
                        ? Theme.accentBlue
                        : Theme.accent)
                if deployEngine.isDeploying {
                    Text("Step \(deployEngine.currentStep)/\(deployEngine.totalSteps) · \(deployEngine.currentDeviceName)")
                        .font(.system(size: 13, weight: .semibold))
                } else if let last = deployEngine.history.first {
                    Text("Last: \(last.projectName) → \(last.deviceNames.joined(separator: ", "))")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("Idle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if deployEngine.isDeploying {
                    Button("Cancel") { deployEngine.cancel() }
                        .foregroundStyle(Theme.error)
                }
            }

            if deployEngine.isDeploying {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            LogView(lines: deployEngine.logLines)
                .frame(minHeight: 360)
        }
        .padding(14)
        .frame(minWidth: 400, minHeight: 480)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
    }
}
