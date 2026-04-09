import Foundation
import Combine

enum DevicePlatform: String, Codable {
    case ios, android
}

enum ConnectionType: String, Codable {
    case usb, wifi
}

struct ConnectedDevice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let platform: DevicePlatform
    let connectionType: ConnectionType
}

enum DeviceScanError: Error, Equatable {
    case flutterNotFound
    case scanFailed(String)
}

@MainActor
final class DeviceManager: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var error: DeviceScanError?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.runScan()
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let devs):
                    self.devices = devs
                    self.error = nil
                case .failure(let err):
                    self.error = err
                    self.devices = []
                }
            }
        }
    }

    nonisolated private static func findFlutter() -> String? {
        let candidates = [
            "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter",
            "\(NSHomeDirectory())/fvm/default/bin/flutter",
            "\(NSHomeDirectory())/development/flutter/bin/flutter",
            "\(NSHomeDirectory())/flutter/bin/flutter"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        // Fall back to `which flutter` via login shell
        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", "command -v flutter"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s, !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) { return s }
        } catch {}
        return nil
    }

    nonisolated private static func runScan() -> Result<[ConnectedDevice], DeviceScanError> {
        guard let flutter = findFlutter() else { return .failure(.flutterNotFound) }

        let p = Process()
        p.launchPath = flutter
        p.arguments = ["devices", "--machine"]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return .failure(.scanFailed(error.localizedDescription))
        }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let arr = json as? [[String: Any]] else {
            return .failure(.scanFailed("Failed to parse flutter devices output"))
        }

        let devs: [ConnectedDevice] = arr.compactMap { dict in
            let isEmu = (dict["emulator"] as? Bool) ?? false
            if isEmu { return nil }
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let target = dict["targetPlatform"] as? String else { return nil }

            let platform: DevicePlatform
            if target.hasPrefix("android") { platform = .android }
            else if target.contains("ios") || target.contains("darwin") { platform = .ios }
            else { return nil }

            let connection: ConnectionType = classifyConnection(id: id, platform: platform)
            return ConnectedDevice(id: id, name: name, platform: platform, connectionType: connection)
        }
        return .success(devs)
    }

    nonisolated private static func classifyConnection(id: String, platform: DevicePlatform) -> ConnectionType {
        // Heuristic per spec: digits-leading or hex-with-dashes → USB; else Wi-Fi.
        let hexDashSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        let idSet = CharacterSet(charactersIn: id)
        let isHexDash = idSet.isSubset(of: hexDashSet) && !id.isEmpty
        let startsWithDigit = id.first.map { $0.isNumber } ?? false
        return (startsWithDigit || isHexDash) ? .usb : .wifi
    }
}
