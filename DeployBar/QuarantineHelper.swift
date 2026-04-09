import Foundation
import AppKit

/// First-run helper that clears macOS Gatekeeper quarantine flags from the
/// Flutter SDK so users don't get hit by 5–10 modal prompts (impellerc,
/// font-subset, gen_snapshot, etc.) the first time they build.
enum QuarantineHelper {
    private static let didClearKey = "quarantineCleared"
    private static let didSkipKey = "quarantineSkipped"

    /// Returns the resolved Flutter SDK root (the directory containing `bin/flutter`)
    /// given the path to the flutter binary, e.g.
    ///   /opt/homebrew/Caskroom/flutter/3.24.0/flutter/bin/flutter
    ///   → /opt/homebrew/Caskroom/flutter/3.24.0/flutter
    static func flutterRoot(forBinary binaryPath: String) -> String? {
        let resolved = (binaryPath as NSString).resolvingSymlinksInPath
        let binDir = (resolved as NSString).deletingLastPathComponent
        let root = (binDir as NSString).deletingLastPathComponent
        return FileManager.default.fileExists(atPath: root) ? root : nil
    }

    /// Check whether any well-known Flutter binaries are still under quarantine.
    /// Returns true if quarantine is present somewhere relevant.
    static func isQuarantined(flutterRoot: String) -> Bool {
        let candidates = [
            "\(flutterRoot)/bin/cache/artifacts/engine/darwin-x64/impellerc",
            "\(flutterRoot)/bin/cache/artifacts/engine/darwin-x64/font-subset",
            "\(flutterRoot)/bin/cache/artifacts/engine/darwin-x64/gen_snapshot_arm64",
            "\(flutterRoot)/bin/cache/artifacts/engine/darwin-arm64/impellerc",
            "\(flutterRoot)/bin/cache/dart-sdk/bin/dart"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if hasQuarantine(path) { return true }
        }
        return false
    }

    private static func hasQuarantine(_ path: String) -> Bool {
        let p = Process()
        p.launchPath = "/usr/bin/xattr"
        p.arguments = ["-p", "com.apple.quarantine", path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Recursively strips com.apple.quarantine from the entire Flutter SDK.
    @discardableResult
    static func clearQuarantine(at flutterRoot: String) -> Bool {
        let p = Process()
        p.launchPath = "/usr/bin/xattr"
        p.arguments = ["-dr", "com.apple.quarantine", flutterRoot]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        let ok = p.terminationStatus == 0
        if ok { UserDefaults.standard.set(true, forKey: didClearKey) }
        return ok
    }

    /// Called from DeployEngine before a deploy. If the SDK is quarantined and
    /// the user hasn't already decided, shows a one-time confirmation alert.
    /// Returns false if the user cancelled (deploy should abort).
    @MainActor
    static func ensureClearedBeforeDeploy(flutterBinary: String) -> Bool {
        // Already cleared previously — nothing to do.
        if UserDefaults.standard.bool(forKey: didClearKey) { return true }
        // User chose to skip — respect that and don't nag.
        if UserDefaults.standard.bool(forKey: didSkipKey) { return true }

        guard let root = flutterRoot(forBinary: flutterBinary) else { return true }
        guard isQuarantined(flutterRoot: root) else {
            // Nothing flagged → mark as cleared so we never check again.
            UserDefaults.standard.set(true, forKey: didClearKey)
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Approve Flutter's bundled tools?"
        alert.informativeText = """
        macOS quarantines binaries downloaded from the internet, including the Flutter SDK at:
        \(root)

        Without approval, you'll see a Gatekeeper prompt for every Flutter tool DeployBar runs (impellerc, font-subset, gen_snapshot…).

        DeployBar can clear these flags in one shot. This is the same as running:
            xattr -dr com.apple.quarantine "\(root)"
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Clear & Continue")
        alert.addButton(withTitle: "Skip (don't ask again)")
        alert.addButton(withTitle: "Cancel Deploy")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return clearQuarantine(at: root)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(true, forKey: didSkipKey)
            return true
        default:
            return false
        }
    }
}
