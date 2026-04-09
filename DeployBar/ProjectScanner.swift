import Foundation
import Combine
import AppKit

struct ScannedProject: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
}

@MainActor
final class ProjectScanner: NSObject, ObservableObject {
    @Published var projects: [ScannedProject] = []
    @Published var lastScanned: Date?
    @Published var isScanning: Bool = false
    @Published var scanDirectories: [String] {
        didSet {
            UserDefaults.standard.set(scanDirectories, forKey: Self.dirsKey)
            refresh()
        }
    }

    static let dirsKey = "scanDirectories"
    static let cacheKey = "cachedProjects"
    static let lastScannedKey = "projectsLastScanned"

    private var query: NSMetadataQuery?

    static var defaultDirs: [String] {
        [
            (NSHomeDirectory() as NSString).appendingPathComponent("Documents/claudecode"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Developer")
        ]
    }

    override init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.dirsKey)
        self.scanDirectories = saved ?? Self.defaultDirs
        super.init()

        // Load cached projects instantly so the list is never empty.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([ScannedProject].self, from: data) {
            self.projects = decoded
        }
        if let ts = UserDefaults.standard.object(forKey: Self.lastScannedKey) as? Date {
            self.lastScanned = ts
        }
        // Kick off a background refresh on launch only.
        refresh()
    }

    func addDirectory(_ path: String) {
        guard !scanDirectories.contains(path) else { return }
        scanDirectories.append(path)
    }

    func removeDirectory(_ path: String) {
        scanDirectories.removeAll { $0 == path }
    }

    // MARK: - Refresh

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        startSpotlightQuery()
    }

    private func startSpotlightQuery() {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemFSName == %@", "pubspec.yaml")
        q.searchScopes = scanDirectories.map { NSURL(fileURLWithPath: $0) as URL }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spotlightFinished(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        query = q
        if !q.start() {
            // Couldn't start — go straight to the shallow fallback.
            finishWithFallback()
        }
    }

    @objc private func spotlightFinished(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        q.disableUpdates()
        defer {
            q.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
            self.query = nil
        }

        var pubspecPaths: [String] = []
        for i in 0..<q.resultCount {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                // Restrict to within configured scan dirs (Spotlight scope can leak above).
                if scanDirectories.contains(where: { path.hasPrefix($0 + "/") }) {
                    pubspecPaths.append(path)
                }
            }
        }

        if pubspecPaths.isEmpty {
            // Spotlight returned nothing — likely indexing not ready. Fall back.
            finishWithFallback()
            return
        }

        let dirs = scanDirectories
        Task.detached(priority: .utility) {
            let projs = Self.loadProjects(fromPubspecPaths: pubspecPaths)
            await MainActor.run {
                self.applyResults(projs, dirs: dirs)
            }
        }
    }

    private func finishWithFallback() {
        let dirs = scanDirectories
        Task.detached(priority: .utility) {
            let pubspecs = Self.shallowScan(dirs: dirs)
            let projs = Self.loadProjects(fromPubspecPaths: pubspecs)
            await MainActor.run {
                self.applyResults(projs, dirs: dirs)
            }
        }
    }

    private func applyResults(_ projs: [ScannedProject], dirs: [String]) {
        let sorted = projs.sorted { $0.lastModified > $1.lastModified }
        self.projects = sorted
        let now = Date()
        self.lastScanned = now
        self.isScanning = false
        if let data = try? JSONEncoder().encode(sorted) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        UserDefaults.standard.set(now, forKey: Self.lastScannedKey)
    }

    // MARK: - Fallback shallow scan (depth ≤ 2)

    nonisolated private static func shallowScan(dirs: [String]) -> [String] {
        let fm = FileManager.default
        let skip: Set<String> = [
            "node_modules", ".dart_tool", "build", ".git",
            "Pods", "DerivedData", "ios/Pods"
        ]
        var pubspecs: [String] = []

        func visit(_ path: String, depth: Int) {
            if depth > 2 { return }
            let pubspec = (path as NSString).appendingPathComponent("pubspec.yaml")
            if fm.fileExists(atPath: pubspec) {
                pubspecs.append(pubspec)
                return // don't descend into a Flutter project
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }
            for entry in entries {
                if entry.hasPrefix(".") { continue }
                if skip.contains(entry) { continue }
                let child = (path as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue {
                    visit(child, depth: depth + 1)
                }
            }
        }

        for root in dirs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue {
                visit(root, depth: 0)
            }
        }
        return pubspecs
    }

    // MARK: - Project loading

    nonisolated private static func loadProjects(fromPubspecPaths pubspecs: [String]) -> [ScannedProject] {
        var seen = Set<String>()
        var results: [ScannedProject] = []
        for pubspec in pubspecs {
            let dir = (pubspec as NSString).deletingLastPathComponent
            if seen.contains(dir) { continue }
            seen.insert(dir)
            if let proj = loadProject(dir: dir, pubspec: pubspec) {
                results.append(proj)
            }
        }
        return results
    }

    nonisolated private static func loadProject(dir: String, pubspec: String) -> ScannedProject? {
        guard let content = try? String(contentsOfFile: pubspec, encoding: .utf8) else { return nil }
        // Skip non-Flutter pubspecs (no flutter dependency block) — keeps the list tight.
        let isFlutter = content.contains("flutter:") || content.contains("sdk: flutter")
        guard isFlutter else { return nil }
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
