import SwiftUI
import AppKit

/// Single-screen welcome window shown on first launch.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))

            Text("Welcome to DeployBar")
                .font(.system(size: 22, weight: .bold))

            VStack(alignment: .leading, spacing: 14) {
                bulletPoint(
                    icon: "iphone",
                    text: "Connect an iOS or Android device"
                )
                bulletPoint(
                    icon: "folder",
                    text: "Select a Flutter project to deploy"
                )
                bulletPoint(
                    icon: "paperplane.fill",
                    text: "Hit Deploy and you're done"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 4) {
                Text("Look for the parachute in your menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\u{2192}")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
            }

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.13, green: 0.77, blue: 0.37))
                    .foregroundStyle(.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 360, height: 420)
    }

    @ViewBuilder
    private func bulletPoint(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 14))
        }
    }
}

/// Controller that manages the welcome window lifecycle.
@MainActor
final class WelcomeWindowController {
    static let hasSeenWelcomeKey = "hasSeenWelcome"
    private var windowController: NSWindowController?

    func showIfNeeded(then openPopover: @escaping () -> Void) {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeenWelcomeKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to DeployBar"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.titlebarAppearsTransparent = true

        let wc = NSWindowController(window: window)
        self.windowController = wc

        window.contentViewController = NSHostingController(
            rootView: WelcomeView {
                window.close()
                openPopover()
            }
        )

        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
    }
}
