import SwiftUI

struct ProjectAnalysisSheet: View {
    let projectPath: String
    let history: [DeployRecord]
    @Environment(\.dismiss) private var dismiss
    @State private var report: AnalysisReport
    @State private var loading: Bool = true

    init(projectPath: String, history: [DeployRecord]) {
        self.projectPath = projectPath
        self.history = history
        self._report = State(initialValue: AnalysisReport(projectPath: projectPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Project Analysis")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Theme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Path") {
                        mono(report.projectPath)
                    }
                    section("Flutter") {
                        mono(loading && report.flutterVersion == "Loading…" ? "Loading…" : report.flutterVersion)
                    }
                    section("Dart Files") {
                        mono("\(report.dartFileCount) files · \(report.totalLines) lines")
                    }
                    section("Dependencies (\(report.dependencies.count))") {
                        if report.dependencies.isEmpty {
                            Text("none").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(report.dependencies, id: \.self) { d in
                                    mono("• \(d)")
                                }
                            }
                        }
                    }
                    if !report.devDependencies.isEmpty {
                        section("Dev Dependencies (\(report.devDependencies.count))") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(report.devDependencies, id: \.self) { d in
                                    mono("• \(d)")
                                }
                            }
                        }
                    }
                    section("Android (build.gradle)") {
                        VStack(alignment: .leading, spacing: 2) {
                            mono("compileSdk: \(report.compileSdk ?? "?")")
                            mono("targetSdk:  \(report.targetSdk ?? "?")")
                            mono("ndkVersion: \(report.ndkVersion ?? "?")")
                        }
                    }
                    section("iOS") {
                        mono("bundleId: \(report.bundleId ?? "?")")
                    }
                    section("Recent .dart files in lib/") {
                        VStack(alignment: .leading, spacing: 2) {
                            if report.recentDartFiles.isEmpty {
                                Text("none").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            } else {
                                let f: DateFormatter = {
                                    let f = DateFormatter()
                                    f.dateFormat = "MM-dd HH:mm"
                                    return f
                                }()
                                ForEach(report.recentDartFiles, id: \.path) { entry in
                                    mono("\(f.string(from: entry.modified))  \(entry.path)")
                                }
                            }
                        }
                    }
                    if let log = report.lastFailureLog, !log.isEmpty {
                        section("Last Failed Deploy") {
                            ScrollView {
                                Text(log)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Theme.error)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 160)
                            .background(Theme.codeBackground)
                            .cornerRadius(4)
                        }
                    }
                }
                .padding(16)
            }

            Divider().background(Theme.divider)
            HStack {
                if loading {
                    ProgressView().controlSize(.small)
                    Text("Analyzing…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                CopyLogButton(textProvider: { report.asPlainText() })
            }
            .padding(12)
        }
        .frame(width: 460, height: 600)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
        .task {
            self.report = await ProjectAnalyzer.analyze(projectPath: projectPath, history: history)
            self.loading = false
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.2)
            content()
        }
    }

    @ViewBuilder
    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
