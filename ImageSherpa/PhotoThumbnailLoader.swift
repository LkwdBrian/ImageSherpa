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
    /// Why a given path couldn't produce a thumbnail — surfaced in the UI (icon + tooltip)
    /// rather than left as an unexplained blank box, since a mixed-content album (videos,
    /// Live Photo companion movies, RAW formats ImageIO can't decode) will always have a
    /// few of these and it isn't a bug.
    enum UnavailableReason {
        case permissionDenied
        case video
        case decodeFailed

        var label: String {
            switch self {
            case .permissionDenied: return "Needs Full Disk Access"
            case .video: return "Video — no thumbnail preview"
            case .decodeFailed: return "Preview unavailable"
            }
        }

        var symbolName: String {
            switch self {
            case .permissionDenied: return "lock.fill"
            case .video: return "video.slash"
            case .decodeFailed: return "photo.badge.exclamationmark"
            }
        }
    }

    enum Result {
        case image(NSImage)
        case unavailable(UnavailableReason)
    }

    /// osxphotos query --json returns videos and Live Photos alongside stills with no type
    /// filter of its own; CGImageSourceCreateThumbnailAtIndex is a still-image API and can
    /// never produce a frame from these regardless of permissions, so they're identified by
    /// extension up front rather than left to fail decode and get misreported as a generic
    /// failure.
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]

    /// Photos library originals (`~/Pictures/*.photoslibrary/originals/...`) are gated by
    /// Full Disk Access, the same TCC category as `Photos.sqlite` (see CLAUDE.md's Framework
    /// Reality Checks). `osxphotos` itself is a separately-granted process identity, so its
    /// `query --json` can succeed and hand back real paths while ImageSherpa.app — a
    /// different binary that has never been granted FDA — still can't read those same files
    /// directly. When that happens, CGImageSourceCreateThumbnailAtIndex fails silently (no
    /// Swift-visible error, just a raw ImageIO console log), so the raw EPERM check here is
    /// what lets the UI tell "needs Full Disk Access" apart from "not a decodable image".
    static func load(path: String, maxPixelSize: CGFloat = 160) -> Result {
        guard isReadable(path: path) else { return .unavailable(.permissionDenied) }

        let ext = (path as NSString).pathExtension.lowercased()
        guard !videoExtensions.contains(ext) else { return .unavailable(.video) }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .unavailable(.decodeFailed) }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .unavailable(.decodeFailed)
        }
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
