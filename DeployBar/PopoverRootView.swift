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
                case .deploy: DeployTabView().environmentObject(deviceManager)
                case .history: HistoryTabView()
                case .settings: SettingsTabView()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Devices · via flutter devices")

                if let err = deviceManager.error {
                    errorView(err)
                } else if deviceManager.devices.isEmpty {
                    emptyState("Plug in or pair a device")
                } else {
                    ForEach(deviceManager.devices) { d in
                        DeviceRowView(device: d)
                    }
                }
            }
            .padding(12)
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
                Text("\(truncatedId) · \(device.platform.rawValue)")
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

    private var truncatedId: String {
        if device.id.count > 16 {
            return String(device.id.prefix(8)) + "…" + String(device.id.suffix(4))
        }
        return device.id
    }
}

struct HistoryTabView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("History").foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct SettingsTabView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Settings").foregroundStyle(.secondary)
            Spacer()
            Button("Quit DeployBar") { NSApp.terminate(nil) }
                .foregroundStyle(.red)
                .padding(.bottom, 16)
        }
    }
}
