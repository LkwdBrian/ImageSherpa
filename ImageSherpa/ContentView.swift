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

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Text("Dependencies").tag(SidebarSelection.dependencies)

                Section("Tools") {
                    ForEach(tools) { tool in
                        Text(tool.displayName).tag(SidebarSelection.tool(tool.id))
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
                        ToolDetailView(tool: tool)
                    } else {
                        DependenciesView()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
