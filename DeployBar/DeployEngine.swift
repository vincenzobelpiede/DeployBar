import Foundation
import Combine
import UserNotifications
import AppKit

enum LogLevel: String, Codable {
    case info, success, warning, error
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: String
    let text: String
    let level: LogLevel
}

struct DeployRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let projectName: String
    let deviceNames: [String]
    let startTime: Date
    let duration: TimeInterval
    let status: Status
    let errorSnippet: String?

    enum Status: String, Codable { case success, failed, cancelled }
}

@MainActor
final class DeployEngine: ObservableObject {
    @Published var isDeploying: Bool = false
    @Published var logLines: [LogLine] = []
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 0
    @Published var currentDeviceName: String = ""
    @Published var history: [DeployRecord] = []

    static let historyKey = "deployHistory"

    private var currentProcess: Process?
    private var cancelled: Bool = false

    init() {
        loadHistory()
        requestNotificationAuthIfNeeded()
    }

    private func postIconState(_ state: String) {
        NotificationCenter.default.post(
            name: Notification.Name("DeployBar.iconStateChanged"),
            object: nil,
            userInfo: ["state": state]
        )
    }

    // MARK: - Public

    func deploy(project: ScannedProject, devices: [ConnectedDevice]) {
        guard !isDeploying, !devices.isEmpty else { return }
        isDeploying = true
        cancelled = false
        logLines.removeAll()
        totalSteps = devices.count
        currentStep = 0
        postIconState("deploying")

        let startTime = Date()
        let deviceNames = devices.map(\.name)
        let projectName = project.name
        let projectPath = project.path

        Task { [weak self] in
            guard let self else { return }
            var anyFailed = false
            var firstError: String?

            for (idx, device) in devices.enumerated() {
                if self.cancelled { break }
                await MainActor.run {
                    self.currentStep = idx + 1
                    self.currentDeviceName = device.name
                    self.appendLog("── Step \(idx + 1)/\(devices.count): \(device.name) ──", level: .info)
                }
                let ok = await self.runSteps(for: device, projectPath: projectPath)
                if !ok {
                    anyFailed = true
                    if firstError == nil {
                        firstError = self.logLines.last(where: { $0.level == .error })?.text
                    }
                    break
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            let status: DeployRecord.Status = self.cancelled ? .cancelled : (anyFailed ? .failed : .success)
            let record = DeployRecord(
                id: UUID(),
                projectName: projectName,
                deviceNames: deviceNames,
                startTime: startTime,
                duration: duration,
                status: status,
                errorSnippet: firstError
            )
            await MainActor.run {
                self.saveHistory(record)
                self.isDeploying = false
                self.currentProcess = nil
                self.notifyComplete(record)
                self.postIconState(record.status == .success ? "idle" : "failed")
            }
        }
    }

    func cancel() {
        cancelled = true
        currentProcess?.terminate()
    }

    // MARK: - Steps

    private func runSteps(for device: ConnectedDevice, projectPath: String) async -> Bool {
        guard let flutter = Self.findFlutter() else {
            await MainActor.run { self.appendLog("flutter not found in PATH", level: .error) }
            return false
        }

        // Always build before install — `flutter install` alone just pushes a
        // stale prebuilt artifact and does NOT rebuild from source.
        let buildArgs: [String]
        switch device.platform {
        case .ios:     buildArgs = ["build", "ios", "--release"]
        case .android: buildArgs = ["build", "apk", "--release"]
        }
        let built = await runCommand(flutter, args: buildArgs, cwd: projectPath)
        if !built { return false }

        return await runCommand(flutter, args: ["install", "-d", device.id, "--release"], cwd: projectPath)
    }

    private func runCommand(_ launchPath: String, args: [String], cwd: String) async -> Bool {
        await MainActor.run {
            self.appendLog("$ \((launchPath as NSString).lastPathComponent) \(args.joined(separator: " ")) (cwd: \((cwd as NSString).lastPathComponent))", level: .info)
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let process = Process()
            process.launchPath = launchPath
            process.arguments = args
            process.currentDirectoryPath = cwd

            // GUI-launched apps inherit a stripped PATH from LaunchServices
            // (/usr/bin:/bin:/usr/sbin:/sbin). flutter build ios needs xcrun,
            // pod, git, ruby, and flutter itself on PATH — otherwise the build
            // stalls silently. Reconstruct a full developer PATH here.
            var env = ProcessInfo.processInfo.environment
            let flutterDir = (launchPath as NSString).deletingLastPathComponent
            let extraPath = [
                flutterDir,
                "/opt/homebrew/bin",
                "/opt/homebrew/sbin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
                "\(NSHomeDirectory())/.pub-cache/bin",
                "\(NSHomeDirectory())/.gem/ruby/bin"
            ].joined(separator: ":")
            if let existing = env["PATH"], !existing.isEmpty {
                env["PATH"] = "\(extraPath):\(existing)"
            } else {
                env["PATH"] = extraPath
            }
            env["HOME"] = NSHomeDirectory()
            // Force flutter to use ANSI-free output so we log clean lines
            env["TERM"] = "dumb"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            // Close stdin explicitly so tools that check isatty don't hang
            process.standardInput = FileHandle.nullDevice

            let handleData: @Sendable (FileHandle) -> Void = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                Task { @MainActor [weak self] in
                    for line in lines {
                        let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }
                        self?.appendLog(trimmed, level: Self.classify(trimmed))
                    }
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = handleData
            errPipe.fileHandleForReading.readabilityHandler = handleData

            process.terminationHandler = { proc in
                // Drain whatever is left before tearing down the pipes so we
                // don't lose the final lines (including error messages).
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let tailOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let tailErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                for tail in [tailOut, tailErr] {
                    if !tail.isEmpty, let text = String(data: tail, encoding: .utf8) {
                        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                        Task { @MainActor [weak self] in
                            for line in lines {
                                let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { continue }
                                self?.appendLog(trimmed, level: Self.classify(trimmed))
                            }
                        }
                    }
                }
                Task { @MainActor [weak self] in
                    self?.appendLog("→ exit \(proc.terminationStatus)", level: proc.terminationStatus == 0 ? .success : .error)
                }
                continuation.resume(returning: proc.terminationStatus == 0)
            }

            do {
                try process.run()
                Task { @MainActor in self.currentProcess = process }
            } catch {
                Task { @MainActor in
                    self.appendLog("Failed to launch: \(error.localizedDescription)", level: .error)
                }
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Helpers

    private func appendLog(_ text: String, level: LogLevel) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        logLines.append(LogLine(timestamp: f.string(from: Date()), text: text, level: level))
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    private static func classify(_ line: String) -> LogLevel {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failure") || lower.contains("✗") {
            return .error
        }
        if lower.contains("warning") { return .warning }
        if line.contains("✓") || lower.contains("success") || lower.contains("built") || lower.contains("installed") {
            return .success
        }
        return .info
    }

    private static func findFlutter() -> String? {
        let candidates = [
            "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter",
            "\(NSHomeDirectory())/fvm/default/bin/flutter",
            "\(NSHomeDirectory())/development/flutter/bin/flutter",
            "\(NSHomeDirectory())/flutter/bin/flutter"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
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

    // MARK: - History

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([DeployRecord].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory(_ record: DeployRecord) {
        history.insert(record, at: 0)
        if history.count > 30 { history = Array(history.prefix(30)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    // MARK: - Notifications

    private func requestNotificationAuthIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyComplete(_ record: DeployRecord) {
        guard UserDefaults.standard.object(forKey: "notifyOnComplete") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        switch record.status {
        case .success:
            content.title = "✅ Deploy succeeded"
            content.body = "\(record.projectName) → \(record.deviceNames.joined(separator: ", "))"
        case .failed:
            content.title = "❌ Deploy failed"
            content.body = "\(record.projectName): \(record.errorSnippet ?? "unknown error")"
        case .cancelled:
            content.title = "⏹ Deploy cancelled"
            content.body = record.projectName
        }
        let req = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
