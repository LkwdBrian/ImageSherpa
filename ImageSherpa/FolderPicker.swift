import AppKit

/// Thin NSOpenPanel wrapper for `folder`/`file` RecipeFields. SwiftUI has no native
/// folder/file picker on macOS, so this is the one place AppKit is unavoidable
/// (see CLAUDE.md's "UI: SwiftUI only" non-negotiable).
enum FolderPicker {
    static func choose(canChooseFiles: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = !canChooseFiles
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
