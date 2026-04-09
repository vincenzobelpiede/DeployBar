import SwiftUI

enum DeployTab: String, CaseIterable, Identifiable {
    case deploy = "Deploy"
    case history = "History"
    case settings = "Settings"
    var id: String { rawValue }
}

struct PopoverRootView: View {
    @State private var tab: DeployTab = .deploy

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
                case .deploy: DeployTabView()
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
    var body: some View {
        VStack {
            Spacer()
            Text("Deploy").foregroundStyle(.secondary)
            Spacer()
        }
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
