import Foundation

struct AnalysisReport: Equatable {
    var projectPath: String
    var flutterVersion: String = "Loading…"
    var dependencies: [String] = []
    var devDependencies: [String] = []
    var recentDartFiles: [(path: String, modified: Date)] = []
    var compileSdk: String?
    var targetSdk: String?
    var ndkVersion: String?
    var bundleId: String?
    var dartFileCount: Int = 0
    var totalLines: Int = 0
    var lastFailureLog: String?

    static func == (lhs: AnalysisReport, rhs: AnalysisReport) -> Bool {
        lhs.projectPath == rhs.projectPath
    }

    func asPlainText() -> String {
        var out: [String] = []
        out.append("DeployBar Project Analysis")
        out.append("==========================")
        out.append("")
        out.append("Path:    \(projectPath)")
        out.append("Flutter: \(flutterVersion)")
        out.append("")
        out.append("── Dart files ──")
        out.append("Files: \(dartFileCount)   Lines: \(totalLines)")
        out.append("")
        out.append("── Dependencies (\(dependencies.count)) ──")
        for d in dependencies { out.append("  • \(d)") }
        if !devDependencies.isEmpty {
            out.append("")
            out.append("── Dev Dependencies (\(devDependencies.count)) ──")
            for d in devDependencies { out.append("  • \(d)") }
        }
        out.append("")
        out.append("── Android (build.gradle) ──")
        out.append("compileSdk: \(compileSdk ?? "?")")
        out.append("targetSdk:  \(targetSdk ?? "?")")
        out.append("ndkVersion: \(ndkVersion ?? "?")")
        out.append("")
        out.append("── iOS ──")
        out.append("bundleId:   \(bundleId ?? "?")")
        out.append("")
        out.append("── Recent .dart files in lib/ ──")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for entry in recentDartFiles {
            out.append("  \(f.string(from: entry.modified))   \(entry.path)")
        }
        if let log = lastFailureLog, !log.isEmpty {
            out.append("")
            out.append("── Last failed deploy log ──")
            out.append(log)
        }
        return out.joined(separator: "\n")
    }
}

enum ProjectAnalyzer {
    static func analyze(projectPath: String, history: [DeployRecord]) async -> AnalysisReport {
        var report = AnalysisReport(projectPath: projectPath)

        report.flutterVersion = await runFlutterVersion()

        let pubspec = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        let (deps, devDeps) = parsePubspec(pubspec)
        report.dependencies = deps
        report.devDependencies = devDeps

        let libDir = (projectPath as NSString).appendingPathComponent("lib")
        let recents = recentDartFiles(libDir: libDir, limit: 5)
        report.recentDartFiles = recents

        let (count, lines) = countDart(libDir: libDir)
        report.dartFileCount = count
        report.totalLines = lines

        let gradle = (projectPath as NSString).appendingPathComponent("android/app/build.gradle")
        let gradleKts = (projectPath as NSString).appendingPathComponent("android/app/build.gradle.kts")
        let gradlePath = FileManager.default.fileExists(atPath: gradle) ? gradle : gradleKts
        if FileManager.default.fileExists(atPath: gradlePath) {
            let (cs, ts, nv) = parseGradle(gradlePath)
            report.compileSdk = cs
            report.targetSdk = ts
            report.ndkVersion = nv
        }

        let pbxproj = (projectPath as NSString).appendingPathComponent("ios/Runner.xcodeproj/project.pbxproj")
        if FileManager.default.fileExists(atPath: pbxproj) {
            report.bundleId = parseBundleId(pbxproj)
        }

        // Pull last failed deploy for this project from history
        let projectName = (projectPath as NSString).lastPathComponent
        if let lastFail = history.first(where: { $0.status == .failed && ($0.projectName == projectName || projectPath.contains($0.projectName)) }) {
            report.lastFailureLog = lastFail.logText ?? lastFail.errorSnippet
        }

        return report
    }

    // MARK: - Flutter version

    private static func runFlutterVersion() async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .utility).async {
                guard let flutter = findFlutter() else {
                    cont.resume(returning: "flutter not found")
                    return
                }
                let p = Process()
                p.launchPath = flutter
                p.arguments = ["--version"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "\((flutter as NSString).deletingLastPathComponent):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env
                do { try p.run() } catch {
                    cont.resume(returning: "error: \(error.localizedDescription)")
                    return
                }
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? "unknown"
                cont.resume(returning: firstLine.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private static func findFlutter() -> String? {
        let candidates = [
            "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter",
            "\(NSHomeDirectory())/fvm/default/bin/flutter",
            "\(NSHomeDirectory())/flutter/bin/flutter"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    // MARK: - pubspec parser (very small YAML subset)

    private static func parsePubspec(_ path: String) -> (deps: [String], dev: [String]) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return ([], []) }
        var deps: [String] = []
        var devDeps: [String] = []
        var section: String? = nil
        for raw in content.components(separatedBy: .newlines) {
            // Strip inline comments
            let line = raw.split(separator: "#").first.map(String.init) ?? raw
            // Top-level keys (no leading whitespace, ends with colon)
            if let firstChar = line.first, !firstChar.isWhitespace {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix(":") {
                    let key = String(trimmed.dropLast())
                    section = key
                    continue
                } else {
                    section = nil
                }
            }
            // Indented child of dependencies/dev_dependencies
            guard let s = section, s == "dependencies" || s == "dev_dependencies" else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Match "name:" or "name: ^1.2.3" — child must have at most one indent level
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            if leadingSpaces < 2 || leadingSpaces > 4 { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                if name.isEmpty || name.hasPrefix("-") { continue }
                if s == "dependencies" { deps.append(name) }
                else { devDeps.append(name) }
            }
        }
        return (deps, devDeps)
    }

    // MARK: - Recent dart files

    private static func recentDartFiles(libDir: String, limit: Int) -> [(String, Date)] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: libDir, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let enumerator = fm.enumerator(atPath: libDir) else { return [] }
        var entries: [(String, Date)] = []
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".dart") else { continue }
            let full = (libDir as NSString).appendingPathComponent(rel)
            if let mod = try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date {
                entries.append((rel, mod))
            }
        }
        return Array(entries.sorted { $0.1 > $1.1 }.prefix(limit))
    }

    // MARK: - Counts

    private static func countDart(libDir: String) -> (count: Int, lines: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: libDir, isDirectory: &isDir), isDir.boolValue else { return (0, 0) }
        guard let enumerator = fm.enumerator(atPath: libDir) else { return (0, 0) }
        var count = 0
        var lines = 0
        for case let rel as String in enumerator {
            guard rel.hasSuffix(".dart") else { continue }
            count += 1
            let full = (libDir as NSString).appendingPathComponent(rel)
            if let content = try? String(contentsOfFile: full, encoding: .utf8) {
                lines += content.split(whereSeparator: { $0 == "\n" }).count
            }
        }
        return (count, lines)
    }

    // MARK: - Gradle

    private static func parseGradle(_ path: String) -> (compileSdk: String?, targetSdk: String?, ndk: String?) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return (nil, nil, nil) }
        func match(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return (
            match(#"compileSdk(?:Version)?\s*[=:]?\s*([^\s\n]+)"#),
            match(#"targetSdk(?:Version)?\s*[=:]?\s*([^\s\n]+)"#),
            match(#"ndkVersion\s*[=:]?\s*"?([^"\s\n]+)"?"#)
        )
    }

    // MARK: - iOS bundle id

    private static func parseBundleId(_ pbxprojPath: String) -> String? {
        guard let text = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else { return nil }
        guard let re = try? NSRegularExpression(pattern: #"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }
}
