//
//  ContentView.swift
//  ImageSherpa
//
//  Created by Brian Cosgrove on 9/10/26.
//

import SwiftUI

private enum SidebarSelection: Hashable {
    case dependencies
    case tool(String)
}

struct ContentView: View {
    private let tools = ToolRegistryLoader.loadAll()
    @State private var selection: SidebarSelection? = .dependencies
    @State private var statuses: [String: PackageStatus] = [:]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Dependencies").tag(SidebarSelection.dependencies)

                Section("Tools") {
                    ForEach(tools) { tool in
                        ToolRow(tool: tool, status: statuses[tool.id])
                            .tag(SidebarSelection.tool(tool.id))
                    }
                }
            }
            .navigationTitle("ImageSherpa")
        } detail: {
            // NavigationSplitView's detail column needs its own NavigationStack: a
            // NavigationLink pushed from the sidebar column can land content here, but
            // without an explicit stack here, a nested NavigationLink(value:) +
            // .navigationDestination(for:) further down (e.g. ToolDetailView's recipe
            // list) has no path to push onto and silently no-ops. Driving detail content
            // from `selection` instead keeps one real stack for both levels of push.
            NavigationStack {
                switch selection {
                case .none, .dependencies:
                    DependenciesView()
                case .tool(let id):
                    if let tool = tools.first(where: { $0.id == id }) {
                        // Not-installed tools would only lead to a doomed-to-fail recipe
                        // run ("command not found"); gate on the same status the
                        // Dependencies tab tracks instead of letting that happen (#12).
                        if statuses[tool.id]?.isInstalled == true {
                            ToolDetailView(tool: tool)
                        } else {
                            ToolNotInstalledView(tool: tool) {
                                selection = .dependencies
                            }
                        }
                    } else {
                        DependenciesView()
                    }
                }
            }
        }
        .task { await refreshAllStatuses() }
        .onChange(of: selection) { _, newValue in
            // Re-check status on every selection change (not just once at launch) so
            // installing a tool in Dependencies and switching back reflects immediately.
            guard case .tool(let id) = newValue, let tool = tools.first(where: { $0.id == id }) else { return }
            Task { await refreshStatus(for: tool) }
        }
    }

    private func refreshAllStatuses() async {
        for tool in tools {
            await refreshStatus(for: tool)
        }
    }

    private func refreshStatus(for tool: ToolDefinition) async {
        statuses[tool.id] = await PackageManagerRouter.status(for: tool)
    }
}

private struct ToolRow: View {
    let tool: ToolDefinition
    let status: PackageStatus?

    var body: some View {
        Text(tool.displayName)
            .foregroundStyle(status?.isInstalled == false ? .secondary : .primary)
    }
}

private struct ToolNotInstalledView: View {
    let tool: ToolDefinition
    let onGoToDependencies: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(tool.displayName) isn't installed")
                .font(.title3.bold())
            Text("Install \(tool.displayName) from the Dependencies tab before running its recipes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Go to Dependencies", action: onGoToDependencies)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(tool.displayName)
    }
}

#Preview {
    ContentView()
}
