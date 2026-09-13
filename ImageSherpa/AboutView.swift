//
//  AboutView.swift
//  ImageSherpa
//

import SwiftUI

struct AboutView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ImageSherpa"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text(appName)
                .font(.title)
                .bold()

            Text("Command-line photo and video tools,\nno command line required.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Version \(version) (\(build))")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Copyright © 2026 So Wired Productions\nAll rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 320)
    }
}

#Preview {
    AboutView()
}
