import AppKit
import ImageIO

/// Generates small downsampled thumbnails for the osxphotos preview grid (#17) via
/// ImageIO's thumbnail API rather than loading full-resolution originals into memory —
/// matters here since a preview can list dozens of photos at once, including large
/// HEIC/RAW originals.
enum PhotoThumbnailLoader {
    static func load(path: String, maxPixelSize: CGFloat = 160) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
