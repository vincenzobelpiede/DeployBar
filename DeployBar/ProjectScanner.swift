import Foundation
import Combine

struct ScannedProject: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
}

@MainActor
final class ProjectScanner: ObservableObject {
    @Published var projects: [ScannedProject] = []
    @Published var scanDirectories: [String] {
        didSet {
            UserDefaults.standard.set(scanDirectories, forKey: Self.dirsKey)
            refresh()
        }
    }

    static let dirsKey = "scanDirectories"

    static var defaultDirs: [String] {
        [
            (NSHomeDirectory() as NSString).appendingPathComponent("Documents/claudecode"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Developer")
        ]
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.dirsKey)
        self.scanDirectories = saved ?? Self.defaultDirs
        refresh()
    }

    func addDirectory(_ path: String) {
        guard !scanDirectories.contains(path) else { return }
        scanDirectories.append(path)
    }

    func removeDirectory(_ path: String) {
        scanDirectories.removeAll { $0 == path }
    }

    func refresh() {
        let dirs = scanDirectories
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.scan(dirs: dirs)
            await MainActor.run {
                self?.projects = found
            }
        }
    }

    nonisolated private static func scan(dirs: [String]) -> [ScannedProject] {
        let fm = FileManager.default
        var results: [ScannedProject] = []
        var seenPaths = Set<String>()

        for root in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            walk(path: root, depth: 0, maxDepth: 3, fm: fm) { dir in
                let pubspec = (dir as NSString).appendingPathComponent("pubspec.yaml")
                if fm.fileExists(atPath: pubspec), !seenPaths.contains(dir) {
                    seenPaths.insert(dir)
                    if let proj = loadProject(dir: dir, pubspec: pubspec) {
                        results.append(proj)
                    }
                    return false // don't recurse into a Flutter project
                }
                return true
            }
        }

        return results.sorted { $0.lastModified > $1.lastModified }
    }

    nonisolated private static func walk(path: String, depth: Int, maxDepth: Int, fm: FileManager, visit: (String) -> Bool) {
        if depth > maxDepth { return }
        let shouldRecurse = visit(path)
        guard shouldRecurse, depth < maxDepth else { return }
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }
        for entry in entries {
            if entry.hasPrefix(".") { continue }
            if ["node_modules", "build", "Pods", "DerivedData", ".git", ".dart_tool"].contains(entry) { continue }
            let child = (path as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue {
                walk(path: child, depth: depth + 1, maxDepth: maxDepth, fm: fm, visit: visit)
            }
        }
    }

    nonisolated private static func loadProject(dir: String, pubspec: String) -> ScannedProject? {
        guard let content = try? String(contentsOfFile: pubspec, encoding: .utf8) else { return nil }
        let name = extractName(from: content) ?? (dir as NSString).lastPathComponent
        let lastMod = latestDartMTime(in: (dir as NSString).appendingPathComponent("lib"))
            ?? (try? FileManager.default.attributesOfItem(atPath: pubspec)[.modificationDate] as? Date)
            ?? Date.distantPast
        return ScannedProject(id: UUID(), name: name, path: dir, lastModified: lastMod)
    }

    nonisolated private static func extractName(from yaml: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                let value = trimmed
                    .dropFirst("name:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    nonisolated private static func latestDartMTime(in libDir: String) -> Date? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: libDir, isDirectory: &isDir), isDir.boolValue else { return nil }
        guard let enumerator = fm.enumerator(atPath: libDir) else { return nil }
        var latest: Date?
        for case let relPath as String in enumerator {
            guard relPath.hasSuffix(".dart") else { continue }
            let full = (libDir as NSString).appendingPathComponent(relPath)
            if let mod = try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date {
                if latest == nil || mod > latest! { latest = mod }
            }
        }
        return latest
    }
}

enum RelativeTime {
    static func short(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        if interval < 86_400 * 30 { return "\(Int(interval / 86_400))d" }
        if interval < 86_400 * 365 { return "\(Int(interval / (86_400 * 30)))mo" }
        return "\(Int(interval / (86_400 * 365)))y"
    }
}
