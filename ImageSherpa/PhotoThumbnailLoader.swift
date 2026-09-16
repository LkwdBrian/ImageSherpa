import AppKit
import ImageIO
#if canImport(Darwin)
import Darwin
#endif

/// Generates small downsampled thumbnails for the osxphotos preview grid (#17) via
/// ImageIO's thumbnail API rather than loading full-resolution originals into memory —
/// matters here since a preview can list dozens of photos at once, including large
/// HEIC/RAW originals.
enum PhotoThumbnailLoader {
    enum Result {
        case image(NSImage)
        case permissionDenied
        case failure
    }

    /// Photos library originals (`~/Pictures/*.photoslibrary/originals/...`) are gated by
    /// Full Disk Access, the same TCC category as `Photos.sqlite` (see CLAUDE.md's Framework
    /// Reality Checks). `osxphotos` itself is a separately-granted process identity, so its
    /// `query --json` can succeed and hand back real paths while ImageSherpa.app — a
    /// different binary that has never been granted FDA — still can't read those same files
    /// directly. When that happens, CGImageSourceCreateThumbnailAtIndex fails silently (no
    /// Swift-visible error, just a raw ImageIO console log), so the raw EPERM check here is
    /// what lets the UI tell "needs Full Disk Access" apart from "not a decodable image".
    static func load(path: String, maxPixelSize: CGFloat = 160) -> Result {
        guard isReadable(path: path) else { return .permissionDenied }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .failure }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return .failure }
        return .image(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
    }

    /// Raw POSIX open()/errno check, same technique as FullDiskAccessCheck — a higher-level
    /// FileManager/Data API doesn't reliably surface EPERM the same way (see CLAUDE.md).
    private static func isReadable(path: String) -> Bool {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}
