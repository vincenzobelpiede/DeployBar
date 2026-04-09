import Foundation
import Combine

enum DevicePlatform: String, Codable {
    case ios, android
}

enum ConnectionType: String, Codable {
    case usb, wifi
}

enum DeviceSource: String, Codable {
    case flutter      // seen by `flutter devices --machine`
    case adbOnly      // seen by adb but not flutter → needs adb install path
}

struct ConnectedDevice: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let platform: DevicePlatform
    let connectionType: ConnectionType
    var source: DeviceSource = .flutter
}

enum DeviceScanError: Error, Equatable {
    case flutterNotFound
    case scanFailed(String)
}

@MainActor
final class DeviceManager: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var error: DeviceScanError?
    @Published var isCached: Bool = false     // true when showing stale cached data

    static let cacheKey = "cachedDevices"

    private var timer: Timer?

    init() {
        // Load cached devices instantly so the popover is never empty.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([ConnectedDevice].self, from: data),
           !decoded.isEmpty {
            self.devices = decoded
            self.isCached = true
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let flutterResult = Self.runFlutterScan()
            let adbDevices = Self.runAdbScan()

            await MainActor.run {
                guard let self else { return }
                let merged: [ConnectedDevice]
                switch flutterResult {
                case .success(let flutterDevs):
                    merged = Self.merge(flutter: flutterDevs, adb: adbDevices)
                    self.error = nil
                case .failure(let err):
                    // If flutter fails, at least surface adb devices.
                    merged = adbDevices
                    self.error = merged.isEmpty ? err : nil
                }
                self.devices = merged
                self.isCached = false
                if let encoded = try? JSONEncoder().encode(merged) {
                    UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
                }
            }
        }
    }

    // MARK: - Merge

    nonisolated private static func merge(flutter: [ConnectedDevice], adb: [ConnectedDevice]) -> [ConnectedDevice] {
        var byId: [String: ConnectedDevice] = [:]
        for d in flutter { byId[d.id] = d }
        for d in adb where byId[d.id] == nil { byId[d.id] = d }
        // Keep flutter order first, then any adb-only
        var result: [ConnectedDevice] = []
        var seen = Set<String>()
        for d in flutter {
            if let merged = byId[d.id], !seen.contains(merged.id) {
                result.append(merged); seen.insert(merged.id)
            }
        }
        for d in adb where !seen.contains(d.id) {
            if let merged = byId[d.id] { result.append(merged); seen.insert(merged.id) }
        }
        return result
    }

    // MARK: - Tool discovery

    nonisolated private static func findExecutable(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/\(name)",
            "\(NSHomeDirectory())/fvm/default/bin/\(name)",
            "\(NSHomeDirectory())/development/flutter/bin/\(name)",
            "\(NSHomeDirectory())/flutter/bin/\(name)"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        let p = Process()
        p.launchPath = "/bin/zsh"
        p.arguments = ["-lc", "command -v \(name)"]
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

    // MARK: - Flutter scan

    nonisolated private static func runFlutterScan() -> Result<[ConnectedDevice], DeviceScanError> {
        guard let flutter = findExecutable("flutter") else { return .failure(.flutterNotFound) }

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

            let connection: ConnectionType = classifyConnection(id: id)
            return ConnectedDevice(id: id, name: name, platform: platform, connectionType: connection, source: .flutter)
        }
        return .success(devs)
    }

    // MARK: - ADB scan

    nonisolated private static func runAdbScan() -> [ConnectedDevice] {
        guard let adb = findExecutable("adb") else { return [] }

        let p = Process()
        p.launchPath = adb
        p.arguments = ["devices", "-l"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [ConnectedDevice] = []
        let lines = text.split(separator: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts[1] == "device" else { continue }
            let id = parts[0]
            // Extract a pretty name from `model:` or `device:` field if present
            var name = id
            for token in parts.dropFirst(2) {
                if token.hasPrefix("model:") {
                    name = String(token.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
                    break
                }
            }
            // Wireless ADB ids look like "192.168.1.27:38791" — contain a dot + colon.
            let connection: ConnectionType = (id.contains(".") && id.contains(":")) ? .wifi : .usb
            result.append(ConnectedDevice(
                id: id,
                name: name,
                platform: .android,
                connectionType: connection,
                source: .adbOnly
            ))
        }
        return result
    }

    nonisolated private static func classifyConnection(id: String) -> ConnectionType {
        let hexDashSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        let idSet = CharacterSet(charactersIn: id)
        let isHexDash = idSet.isSubset(of: hexDashSet) && !id.isEmpty
        let startsWithDigit = id.first.map { $0.isNumber } ?? false
        if id.contains(".") && id.contains(":") { return .wifi }
        return (startsWithDigit || isHexDash) ? .usb : .wifi
    }
}
