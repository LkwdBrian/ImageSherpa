import AppKit

/// Detects the specific failure signature of a Full Disk Access denial and offers a way to
/// jump straight to the relevant System Settings pane. Needed because tools like osxphotos
/// read the Photos library's SQLite file directly rather than through PhotoKit, so they're
/// gated by Full Disk Access, not a per-app Photos/Camera/Mic-style prompt — and macOS
/// doesn't auto-populate the Full Disk Access list after a denied attempt the way it does
/// for those other categories, so a user has no way to discover this without being told.
/// AppKit (NSWorkspace) is an unavoidable exception here per CLAUDE.md's UI Non-Negotiables,
/// same as FolderPicker's NSOpenPanel — there's no SwiftUI-only way to open a System
/// Settings pane.
enum PermissionHelp {
    /// "Operation not permitted" is the generic macOS errno string for an EPERM denial,
    /// which is what a Full-Disk-Access-gated file read surfaces as. It's a heuristic, not
    /// a certainty (a different EPERM could in theory trigger it), but it's the same
    /// signature seen from real osxphotos runs against a protected Photos library, and the
    /// fallback (manual text entry / raw log output) stays visible either way if the guess
    /// is wrong.
    static func looksLikeFullDiskAccessDenial(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("Operation not permitted")
    }

    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
