//
//  ContentView.swift
//  ImageSherpa
//
//  Created by Brian Cosgrove on 9/10/26.
//

import SwiftUI

struct ContentView: View {
    private let tools = ToolRegistryLoader.loadAll()

    var body: some View {
        NavigationSplitView {
            NavigationStack {
                List {
                    NavigationLink("Dependencies") {
                        DependenciesView()
                    }

                    Section("Tools") {
                        ForEach(tools) { tool in
                            NavigationLink(tool.displayName) {
                                ToolDetailView(tool: tool)
                            }
                        }
                    }
                }
                .navigationTitle("ImageSherpa")
            }
        } detail: {
            DependenciesView()
        }
    }
}

#Preview {
    ContentView()
}
