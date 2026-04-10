import SwiftUI
import Foundation

struct PairAndroidView: View {
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void

    @State private var pairAddress: String = ""
    @State private var pairCode: String = ""
    @State private var connectAddress: String = ""
    @State private var step: Step = .pair
    @State private var status: String = ""
    @State private var isWorking: Bool = false
    @State private var isError: Bool = false

    enum Step { case pair, connect, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pair Android over Wi-Fi")
                .font(.system(size: 14, weight: .bold))

            Text("On your Android device:\nSettings → System → Developer options → Wireless debugging → Pair device with pairing code")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(Theme.divider)

            switch step {
            case .pair:
                fieldLabel("Pairing IP:port (e.g. 192.168.1.27:33581)")
                TextField("", text: $pairAddress)
                    .textFieldStyle(.roundedBorder)
                fieldLabel("6-digit pairing code")
                TextField("", text: $pairCode)
                    .textFieldStyle(.roundedBorder)
                actionButton(title: isWorking ? "Pairing…" : "Pair") {
                    runPair()
                }
                .disabled(isWorking || pairAddress.isEmpty || pairCode.isEmpty)

            case .connect:
                Text("✓ Paired").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Now go back to the Wireless debugging screen and copy the IP:port shown at the top (different from the pairing port).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                fieldLabel("Connect IP:port")
                TextField("", text: $connectAddress)
                    .textFieldStyle(.roundedBorder)
                actionButton(title: isWorking ? "Connecting…" : "Connect") {
                    runConnect()
                }
                .disabled(isWorking || connectAddress.isEmpty)

            case .done:
                Text("✓ Connected — refreshing devices…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isError ? Theme.error : Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
            .tracking(1.2)
    }

    @ViewBuilder
    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.accent)
                .foregroundStyle(Theme.accentLabel)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func runPair() {
        isWorking = true
        isError = false
        status = "Running adb pair…"
        let address = pairAddress.trimmingCharacters(in: .whitespaces)
        let code = pairCode.trimmingCharacters(in: .whitespaces)
        Task.detached {
            let result = AdbRunner.pair(address: address, code: code)
            await MainActor.run {
                self.isWorking = false
                self.status = result.output
                if result.success {
                    self.step = .connect
                    self.isError = false
                } else {
                    self.isError = true
                }
            }
        }
    }

    private func runConnect() {
        isWorking = true
        isError = false
        status = "Running adb connect…"
        let address = connectAddress.trimmingCharacters(in: .whitespaces)
        Task.detached {
            let result = AdbRunner.connect(address: address)
            await MainActor.run {
                self.isWorking = false
                self.status = result.output
                if result.success {
                    self.step = .done
                    self.isError = false
                    self.onComplete()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.dismiss()
                    }
                } else {
                    self.isError = true
                }
            }
        }
    }
}

enum AdbRunner {
    struct Result { let success: Bool; let output: String }

    static func pair(address: String, code: String) -> Result {
        runAdb(args: ["pair", address, code])
    }

    static func connect(address: String) -> Result {
        runAdb(args: ["connect", address])
    }

    private static func runAdb(args: [String]) -> Result {
        guard let adb = findAdb() else {
            return Result(success: false, output: "adb not found in PATH. Install Android platform-tools.")
        }
        let p = Process()
        p.launchPath = adb
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        do { try p.run() } catch {
            return Result(success: false, output: error.localizedDescription)
        }
        p.waitUntilExit()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let combined = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")
        return Result(success: p.terminationStatus == 0, output: combined.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func findAdb() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }
}
