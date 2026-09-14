import SwiftUI

/// Tab showing every registered tool's Homebrew install status, with install/uninstall
/// actions. This is the piece every recipe depends on, per CLAUDE.md's build order.
struct DependenciesView: View {
    @State private var tools: [ToolDefinition] = ToolRegistryLoader.loadAll()
    @State private var statuses: [String: PackageStatus] = [:]
    @State private var busyToolIDs: Set<String> = []
    @State private var logLines: [String] = []
    @State private var fullDiskAccessDenied = FullDiskAccessCheck.isDenied()

    private var toolsNeedingFullDiskAccess: [ToolDefinition] {
        tools.filter { $0.needsFullDiskAccess == true }
    }

    /// Install methods at least one registered tool needs but whose manager isn't present
    /// (e.g. Homebrew or pipx not installed) — surfaced as a banner per method rather than
    /// a single hardcoded "Homebrew isn't installed" check, so this scales as install
    /// methods are added (see PackageManagerRouter).
    private var missingManagers: [String] {
        Set(tools.map(\.installMethod))
            .filter { !PackageManagerRouter.isAvailable(for: $0) }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(missingManagers, id: \.self) { method in
                Label(missingManagerMessage(for: method), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding()
            }

            List {
                if !toolsNeedingFullDiskAccess.isEmpty {
                    Section("System Access") {
                        FullDiskAccessRow(
                            toolNames: toolsNeedingFullDiskAccess.map(\.displayName),
                            isDenied: fullDiskAccessDenied,
                            onOpenSettings: { PermissionHelp.openFullDiskAccessSettings() },
                            onRecheck: { fullDiskAccessDenied = FullDiskAccessCheck.isDenied() }
                        )
                    }
                }

                Section("Tools") {
                    ForEach(tools) { tool in
                        DependencyRow(
                            tool: tool,
                            status: statuses[tool.id],
                            isBusy: busyToolIDs.contains(tool.id),
                            isManagerAvailable: PackageManagerRouter.isAvailable(for: tool.installMethod),
                            onInstall: { await installOrUninstall(tool, install: true) },
                            onUninstall: { await installOrUninstall(tool, install: false) }
                        )
                    }
                }
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

    private func missingManagerMessage(for method: String) -> String {
        switch method {
        case "brew": return "Homebrew isn't installed. Install it from brew.sh before managing these tools."
        case "pipx": return "pipx isn't installed. Install it with `brew install pipx` before managing these tools."
        default: return "No install manager available for \"\(method)\"."
        }
    }

    private func refreshAllStatuses() async {
        for tool in tools {
            statuses[tool.id] = await PackageManagerRouter.status(for: tool)
        }
    }

    private func installOrUninstall(_ tool: ToolDefinition, install: Bool) async {
        busyToolIDs.insert(tool.id)
        logLines.removeAll()
        defer { busyToolIDs.remove(tool.id) }

        let exitCode: Int32
        if install {
            exitCode = await PackageManagerRouter.install(tool: tool) { logLines.append($0) }
        } else {
            exitCode = await PackageManagerRouter.uninstall(tool: tool) { logLines.append($0) }
        }

        if exitCode != 0 {
            logLines.append("\nExited with status \(exitCode).")
        }
        statuses[tool.id] = await PackageManagerRouter.status(for: tool)
    }
}

private struct DependencyRow: View {
    let tool: ToolDefinition
    let status: PackageStatus?
    let isBusy: Bool
    let isManagerAvailable: Bool
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
                .disabled(!isManagerAvailable)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Always-visible status row (not just a warning-when-missing banner) for Full Disk
/// Access, the same way DependencyRow always shows a tool's install status. The check
/// itself runs in-process (FullDiskAccessCheck), not by shelling out to a CLI tool — macOS
/// has no query API for this, so it probes a known-gated file directly and reads errno.
private struct FullDiskAccessRow: View {
    let toolNames: [String]
    let isDenied: Bool
    let onOpenSettings: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Full Disk Access").font(.headline)
                Text("Needed for \(toolNames.joined(separator: ", ")) to read your Photos library directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isDenied ? "Not granted" : "Granted")
                    .font(.caption2)
                    .foregroundStyle(isDenied ? .orange : .green)
            }

            Spacer()

            if isDenied {
                Button("Open Settings…", action: onOpenSettings)
            }
            Button {
                onRecheck()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Recheck")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DependenciesView()
}
