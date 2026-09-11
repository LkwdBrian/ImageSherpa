//
//  ContentView.swift
//  ImageSherpa
//
//  Created by Brian Cosgrove on 9/10/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Dependencies") {
                    DependenciesView()
                }
            }
            .navigationTitle("ImageSherpa")
        } detail: {
            DependenciesView()
        }
    }
}

#Preview {
    ContentView()
}
