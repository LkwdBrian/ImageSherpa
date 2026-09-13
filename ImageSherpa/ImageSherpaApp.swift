//
//  ImageSherpaApp.swift
//  ImageSherpa
//
//  Created by Brian Cosgrove on 9/10/26.
//

import SwiftUI

@main
struct ImageSherpaApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ImageSherpa") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About ImageSherpa", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
