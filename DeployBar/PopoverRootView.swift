import SwiftUI

enum DeployTab: String, CaseIterable, Identifiable {
    case deploy = "Deploy"
    case history = "History"
    case settings = "Settings"
    var id: String { rawValue }
}

struct PopoverRootView: View {
    @State private var tab: DeployTab = .deploy
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var projectScanner = ProjectScanner()
    @EnvironmentObject var deployEngine: DeployEngine
    @AppStorage("lastProjectPath") private var lastProjectPath: String = ""
    @AppStorage("lastDeviceId") private var lastDeviceId: String = ""
    @State private var showingPair: Bool = false

    private var flutterMissing: Bool {
        if case .flutterNotFound = deviceManager.error { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if flutterMissing {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Flutter not found in PATH")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.15))
                .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
            }
            Picker("", selection: $tab) {
                ForEach(DeployTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            Group {
                switch tab {
                case .deploy:
                    DeployTabView(
                        selectedProjectPath: $lastProjectPath,
                        selectedDeviceId: $lastDeviceId,
                        showingPair: $showingPair
                    )
                        .environmentObject(deviceManager)
                        .environmentObject(projectScanner)
                        .environmentObject(deployEngine)
                        .sheet(isPresented: $showingPair) {
                            PairAndroidView {
                                deviceManager.refresh()
                            }
                        }
                case .history: HistoryTabView().environmentObject(deployEngine)
                case .settings: SettingsTabView().environmentObject(projectScanner)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 360, height: 700)
        .background(Color(red: 0.094, green: 0.094, blue: 0.106))
        .foregroundStyle(.white)
    }
}

struct DeployTabView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var projectScanner: ProjectScanner
    @EnvironmentObject var deployEngine: DeployEngine
    @Binding var selectedProjectPath: String
    @Binding var selectedDeviceId: String
    @Binding var showingPair: Bool

    private var selectedProject: ScannedProject? {
        projectScanner.projects.first { $0.path == selectedProjectPath }
    }

    private var selectedDevice: ConnectedDevice? {
        deviceManager.devices.first { $0.id == selectedDeviceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Color.clear.frame(height: 0)
                    .onChange(of: projectScanner.projects) { _, projs in
                        if projectScanner.projects.first(where: { $0.path == selectedProjectPath }) == nil,
                           let first = projs.first {
                            selectedProjectPath = first.path
                        }
                    }
                    .onChange(of: deviceManager.devices) { _, devs in
                        if deviceManager.devices.first(where: { $0.id == selectedDeviceId }) == nil,
                           let first = devs.first {
                            selectedDeviceId = first.id
                        }
                    }
                    .onAppear {
                        if selectedProjectPath.isEmpty || projectScanner.projects.first(where: { $0.path == selectedProjectPath }) == nil,
                           let first = projectScanner.projects.first {
                            selectedProjectPath = first.path
                        }
                        if selectedDeviceId.isEmpty || deviceManager.devices.first(where: { $0.id == selectedDeviceId }) == nil,
                           let first = deviceManager.devices.first {
                            selectedDeviceId = first.id
                        }
                    }
                VStack(alignment: .leading, spacing: 14) {
                    if deployEngine.isDeploying {
                        deployingSection
                    } else {
                        devicesAndProjectsSection
                    }
                }
                .padding(12)
            }

            Divider().background(Color(white: 0.17))
            deployButtonBar
                .padding(12)
        }
    }

    @ViewBuilder
    private var devicesAndProjectsSection: some View {
        HStack(spacing: 6) {
            sectionLabel("Flutter Projects")
            Spacer()
            if let ts = projectScanner.lastScanned {
                Text("scanned \(RelativeTime.short(from: ts)) ago")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
            }
            Button {
                projectScanner.refresh()
            } label: {
                Image(systemName: projectScanner.isScanning ? "arrow.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
            .disabled(projectScanner.isScanning)
        }
        if projectScanner.projects.isEmpty {
            emptyState("No Flutter projects found. Add a folder in Settings.")
        } else {
            VStack(spacing: 5) {
                ForEach(projectScanner.projects) { p in
                    ProjectRowView(
                        project: p,
                        selected: selectedProjectPath == p.path
                    ) {
                        selectedProjectPath = p.path
                    }
                }
            }
        }

        Divider().background(Color(white: 0.17))

        HStack(spacing: 6) {
            sectionLabel("Devices · flutter + adb")
            if deviceManager.isCached {
                Text("cached")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(white: 0.2))
                    .foregroundStyle(Color(white: 0.55))
                    .cornerRadius(3)
            }
            Spacer()
        }
        if let err = deviceManager.error {
            errorView(err)
        } else if deviceManager.devices.isEmpty {
            emptyState("Plug in or pair a device")
        } else {
            VStack(spacing: 5) {
                ForEach(deviceManager.devices) { d in
                    DeviceRowView(
                        device: d,
                        selected: selectedDeviceId == d.id
                    ) {
                        selectedDeviceId = d.id
                    }
                }
            }
        }
        Button {
            showingPair = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Pair Android over Wi-Fi")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(white: 0.122))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
    }

    @ViewBuilder
    private var deployingSection: some View {
        sectionLabel("Step \(deployEngine.currentStep)/\(deployEngine.totalSteps) · \(deployEngine.currentDeviceName)")
        ProgressView()
            .progressViewStyle(.linear)
            .tint(Color(red: 0.13, green: 0.77, blue: 0.37))
        LogView(lines: deployEngine.logLines)
    }

    @ViewBuilder
    private var deployButtonBar: some View {
        if deployEngine.isDeploying {
            Button {
                deployEngine.cancel()
            } label: {
                Text("⏹ Cancel")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.15))
                    .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        } else {
            let canDeploy = selectedProject != nil && selectedDevice != nil
            Button {
                guard let proj = selectedProject, let dev = selectedDevice else { return }
                deployEngine.deploy(project: proj, devices: [dev])
            } label: {
                Text(canDeploy
                     ? "🚀 Deploy → \(selectedDevice?.name ?? "")"
                     : "Select a project and a device")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canDeploy
                        ? Color(red: 0.13, green: 0.77, blue: 0.37)
                        : Color(white: 0.2))
                    .foregroundStyle(canDeploy ? Color.black : Color(white: 0.5))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(!canDeploy)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(white: 0.44))
            .tracking(1.5)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    @ViewBuilder
    private func errorView(_ err: DeviceScanError) -> some View {
        switch err {
        case .flutterNotFound:
            Text("Flutter not found — install from flutter.dev")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        case .scanFailed(let msg):
            Text("Scan failed: \(msg)")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                .padding(.vertical, 16)
        }
    }
}

struct DeviceRowView: View {
    let device: ConnectedDevice
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
        HStack(spacing: 9) {
            Text(device.platform == .ios ? "📱" : "🤖")
                .font(.system(size: 18))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(truncatedId(device.id)) · \(device.platform.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .lineLimit(1)
            }
            Spacer()
            if device.source == .adbOnly {
                Text("ADB")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.18))
                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                    .cornerRadius(4)
            }
            Text(device.connectionType == .usb ? "USB" : "Wi-Fi")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(device.connectionType == .usb
                    ? Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.15)
                    : Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.15))
                .foregroundStyle(device.connectionType == .usb
                    ? Color(red: 0.13, green: 0.77, blue: 0.37)
                    : Color(red: 0.23, green: 0.51, blue: 0.96))
                .cornerRadius(4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(selected
            ? Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.05)
            : Color(white: 0.122))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func truncatedId(_ id: String) -> String {
        if id.count > 16 {
            return String(id.prefix(8)) + "…" + String(id.suffix(4))
        }
        return id
    }
}

struct ProjectRowView: View {
    let project: ScannedProject
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text("FLT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .frame(width: 30)
                .padding(.vertical, 3)
                .background(Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.15))
                .foregroundStyle(Color(red: 0.23, green: 0.51, blue: 0.96))
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(shortenPath(project.path))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .lineLimit(1)
            }
            Spacer()
            Text(RelativeTime.short(from: project.lastModified))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.44))
            Button {
                openInTerminal(project.path)
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
            .help("Open in Terminal")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(selected
            ? Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.05)
            : Color(white: 0.122))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .foregroundStyle(.white)
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func openInTerminal(_ path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \\\"\(path)\\\"\"\ntell application \"Terminal\" to activate"
        if let src = NSAppleScript(source: script) {
            var err: NSDictionary?
            src.executeAndReturnError(&err)
        }
    }
}

struct LogView: View {
    let lines: [LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.timestamp)
                                .foregroundStyle(Color(white: 0.44))
                            Text(line.text)
                                .foregroundStyle(colorFor(line.level))
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 220)
            .background(Color(white: 0.067))
            .cornerRadius(6)
            .onChange(of: lines.count) { _, _ in
                if let last = lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func colorFor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return Color(white: 0.75)
        case .success: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .warning: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .error: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}

struct HistoryTabView: View {
    @EnvironmentObject var deployEngine: DeployEngine

    private var recentThree: [DeployRecord] { Array(deployEngine.history.prefix(3)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !recentThree.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(recentThree) { rec in
                            HStack(spacing: 8) {
                                Text(rec.status == .success ? "✅" : rec.status == .failed ? "❌" : "⏹")
                                Text("\(rec.projectName) → \(rec.deviceNames.joined(separator: ", "))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(rec.duration))s")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(toastBg(rec.status))
                            .foregroundStyle(toastFg(rec.status))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(toastFg(rec.status).opacity(0.25), lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                    }
                    Divider().background(Color(white: 0.17))
                    Text("ALL DEPLOYS")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.44))
                        .tracking(1.5)
                }
                if deployEngine.history.isEmpty {
                    Text("No deploys yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    ForEach(deployEngine.history) { rec in
                        HStack(spacing: 9) {
                            Text(badgeText(rec.status))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .frame(width: 30, height: 16)
                                .background(badgeColor(rec.status).opacity(0.15))
                                .foregroundStyle(badgeColor(rec.status))
                                .cornerRadius(4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(rec.projectName) → \(rec.deviceNames.joined(separator: ", "))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text("\(RelativeTime.short(from: rec.startTime)) ago · \(Int(rec.duration))s")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.44))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.122))
                        .cornerRadius(6)
                    }

                    Button("Clear History") { deployEngine.clearHistory() }
                        .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(12)
        }
    }

    private func badgeText(_ s: DeployRecord.Status) -> String {
        switch s { case .success: "OK"; case .failed: "ERR"; case .cancelled: "CXL" }
    }

    private func badgeColor(_ s: DeployRecord.Status) -> Color {
        switch s {
        case .success: Color(red: 0.13, green: 0.77, blue: 0.37)
        case .failed: Color(red: 0.94, green: 0.27, blue: 0.27)
        case .cancelled: Color(white: 0.5)
        }
    }

    private func toastBg(_ s: DeployRecord.Status) -> Color {
        badgeColor(s).opacity(0.15)
    }
    private func toastFg(_ s: DeployRecord.Status) -> Color { badgeColor(s) }
}

struct SettingsTabView: View {
    @AppStorage(StatusIcon.defaultsKey) private var iconName: String = "hammer.fill"
    @AppStorage("notifyOnComplete") private var notifyOnComplete: Bool = true
    @AppStorage("defaultBuildMode") private var defaultBuildMode: String = "release"
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @EnvironmentObject var projectScanner: ProjectScanner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SCAN FOLDERS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .tracking(1.5)
                VStack(spacing: 5) {
                    ForEach(projectScanner.scanDirectories, id: \.self) { dir in
                        HStack(spacing: 8) {
                            Text(shortenPath(dir))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                projectScanner.removeDirectory(dir)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color(white: 0.44))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.122))
                        .cornerRadius(6)
                    }
                    Button {
                        addFolder()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add folder").font(.system(size: 11, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.122))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                }

                Text("BUILD & NOTIFICATIONS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .tracking(1.5)
                VStack(spacing: 5) {
                    Toggle("Notify on complete", isOn: $notifyOnComplete)
                        .font(.system(size: 11))
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .font(.system(size: 11))
                        .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.isEnabled = v }
                    Picker("Default build mode", selection: $defaultBuildMode) {
                        Text("release").tag("release")
                        Text("debug").tag("debug")
                    }
                    .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .padding(9)
                .background(Color(white: 0.122))
                .cornerRadius(6)

                Text("MENU BAR ICON")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .tracking(1.5)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(StatusIcon.options) { opt in
                        Button {
                            iconName = opt.id
                            NotificationCenter.default.post(name: StatusIcon.changedNotification, object: nil)
                        } label: {
                            Image(systemName: opt.id)
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .background(iconName == opt.id
                                    ? Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.18)
                                    : Color(white: 0.122))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(iconName == opt.id
                                            ? Color(red: 0.13, green: 0.77, blue: 0.37)
                                            : Color.clear, lineWidth: 1.5)
                                )
                                .foregroundStyle(iconName == opt.id
                                    ? Color(red: 0.13, green: 0.77, blue: 0.37)
                                    : Color.white.opacity(0.85))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(opt.label)
                    }
                }

                Spacer(minLength: 24)

                DisclosureGroup {
                    ScrollView {
                        Text(Self.changelog)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(white: 0.067))
                    .cornerRadius(6)
                } label: {
                    Text("What's New")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(Self.versionString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.44))
                    .frame(maxWidth: .infinity, alignment: .center)

                Button("Quit DeployBar") { NSApp.terminate(nil) }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "DeployBar v\(v) (build \(b))"
    }

    private static let changelog: String = """
v1.0.0
- One-click Flutter deploy to iOS and Android
- Smart project scanner with Spotlight
- Device caching for instant launch
- Wireless Android pairing wizard
- Deploy history with live log
- Launch at Login
"""

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            projectScanner.addDirectory(url.path)
        }
    }
}
