import Foundation

/// Full Disk Access has no query API — unlike Photos/Camera/Mic/Contacts, there's no
/// `authorizationStatus()` equivalent to ask "is this granted?" ahead of time. The standard
/// workaround (used by most third-party apps that need to detect this) is to probe a path
/// that's reliably present and reliably Full-Disk-Access-gated on any Mac, and see whether
/// reading it fails with EPERM specifically.
enum FullDiskAccessCheck {
    /// The TCC database itself: core macOS infrastructure guaranteed to exist on every Mac
    /// (unlike, say, Safari's CloudTabs.db, which only exists if iCloud Tabs sync has ever
    /// been used — confirmed missing on this machine, which silently made an earlier version
    /// of this probe always report "granted" regardless of the real state) and reliably
    /// Full-Disk-Access-gated.
    private static let probePath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"

    /// Checks the raw POSIX errno rather than a higher-level FileManager/Data API, since
    /// only EPERM unambiguously means "TCC denied this". ENOENT (the file just isn't there
    /// — e.g. iCloud Tabs was never used) must not be treated the same way, or this would
    /// wrongly flag Full Disk Access as missing for people it doesn't apply to.
    static func isDenied() -> Bool {
        let fd = open(probePath, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return false
        }
        return errno == EPERM
    }
}
