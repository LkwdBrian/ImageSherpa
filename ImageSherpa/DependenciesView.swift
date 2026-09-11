import SwiftUI

/// Tab showing every registered tool's Homebrew install status, with install/uninstall
/// actions. This is the piece every recipe depends on, per CLAUDE.md's build order.
struct DependenciesView: View {
    @State private var tools: [ToolDefinition] = ToolRegistryLoader.loadAll()
    @State private var statuses: [String: HomebrewManager.FormulaStatus] = [:]
    @State private var busyToolIDs: Set<String> = []
    @State private var logLines: [String] = []
    @State private var homebrewInstalled = HomebrewManager.isHomebrewInstalled()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !homebrewInstalled {
                Label(
                    "Homebrew isn't installed. Install it from brew.sh before managing tools here.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .padding()
            }

            List(tools) { tool in
                DependencyRow(
                    tool: tool,
                    status: statuses[tool.id],
                    isBusy: busyToolIDs.contains(tool.id),
                    isHomebrewInstalled: homebrewInstalled,
                    onInstall: { await installOrUninstall(tool, install: true) },
                    onUninstall: { await installOrUninstall(tool, install: false) }
                )
            }

            if !logLines.isEmpty {
                Divider()
                ScrollView {
                    Text(logLines.joined())
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 140)
            }
        }
        .navigationTitle("Dependencies")
        .task { await refreshAllStatuses() }
    }

    private func refreshAllStatuses() async {
        for tool in tools {
            statuses[tool.id] = await HomebrewManager.status(forFormula: tool.formula)
        }
    }

    private func installOrUninstall(_ tool: ToolDefinition, install: Bool) async {
        busyToolIDs.insert(tool.id)
        logLines.removeAll()
        defer { busyToolIDs.remove(tool.id) }

        let exitCode: Int32
        if install {
            exitCode = await HomebrewManager.install(formula: tool.formula) { logLines.append($0) }
        } else {
            exitCode = await HomebrewManager.uninstall(formula: tool.formula) { logLines.append($0) }
        }

        if exitCode != 0 {
            logLines.append("\nExited with status \(exitCode).")
        }
        statuses[tool.id] = await HomebrewManager.status(forFormula: tool.formula)
    }
}

private struct DependencyRow: View {
    let tool: ToolDefinition
    let status: HomebrewManager.FormulaStatus?
    let isBusy: Bool
    let isHomebrewInstalled: Bool
    let onInstall: () async -> Void
    let onUninstall: () async -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(tool.displayName).font(.headline)
                Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                if let status, status.isInstalled {
                    Text("Installed" + (status.installedVersion.map { " · v\($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if status != nil {
                    Text("Not installed").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isBusy {
                ProgressView().controlSize(.small)
            } else if let status {
                Button(status.isInstalled ? "Uninstall" : "Install") {
                    Task {
                        if status.isInstalled {
                            await onUninstall()
                        } else {
                            await onInstall()
                        }
                    }
                }
                .disabled(!isHomebrewInstalled)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DependenciesView()
}
