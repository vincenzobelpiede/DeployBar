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
    @StateObject private var deployEngine = DeployEngine()
    @State private var selectedProjectId: UUID?

    var body: some View {
        VStack(spacing: 0) {
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
                    DeployTabView(selectedProjectId: $selectedProjectId)
                        .environmentObject(deviceManager)
                        .environmentObject(projectScanner)
                        .environmentObject(deployEngine)
                case .history: HistoryTabView().environmentObject(deployEngine)
                case .settings: SettingsTabView().environmentObject(projectScanner)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 360, height: 520)
        .background(Color(red: 0.094, green: 0.094, blue: 0.106))
        .foregroundStyle(.white)
    }
}

struct DeployTabView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var projectScanner: ProjectScanner
    @EnvironmentObject var deployEngine: DeployEngine
    @Binding var selectedProjectId: UUID?

    private var selectedProject: ScannedProject? {
        projectScanner.projects.first { $0.id == selectedProjectId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
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
        sectionLabel("Devices · via flutter devices")
        if let err = deviceManager.error {
            errorView(err)
        } else if deviceManager.devices.isEmpty {
            emptyState("Plug in or pair a device")
        } else {
            VStack(spacing: 5) {
                ForEach(deviceManager.devices) { d in
                    DeviceRowView(device: d)
                }
            }
        }

        Divider().background(Color(white: 0.17))

        sectionLabel("Flutter Projects")
        if projectScanner.projects.isEmpty {
            emptyState("No Flutter projects found. Add a folder in Settings.")
        } else {
            VStack(spacing: 5) {
                ForEach(projectScanner.projects) { p in
                    ProjectRowView(
                        project: p,
                        selected: selectedProjectId == p.id
                    ) {
                        selectedProjectId = p.id
                    }
                }
            }
        }
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
            let canDeploy = selectedProject != nil && !deviceManager.devices.isEmpty
            Button {
                guard let proj = selectedProject else { return }
                deployEngine.deploy(project: proj, devices: deviceManager.devices)
            } label: {
                Text(canDeploy
                     ? "🚀 Deploy → \(deviceManager.devices.map(\.name).joined(separator: ", "))"
                     : "Select a project and connect a device")
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

    var body: some View {
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
        .padding(.vertical, 7)
        .background(Color(white: 0.122))
        .cornerRadius(6)
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
        Button(action: onTap) {
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
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
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

    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                        .padding(.vertical, 7)
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
}

struct SettingsTabView: View {
    @AppStorage(StatusIcon.defaultsKey) private var iconName: String = "hammer.fill"
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
                        .padding(.vertical, 7)
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
                        .padding(.vertical, 7)
                        .background(Color(white: 0.122))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                }

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
