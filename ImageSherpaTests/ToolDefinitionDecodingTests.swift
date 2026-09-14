import Foundation
import Testing
@testable import ImageSherpa

/// Decodes each bundled Registry/*.json straight from disk (not via
/// ToolRegistryLoader/Bundle.main, which points at the test runner's own bundle, not
/// ImageSherpa.app's Resources) to catch schema regressions like a typo'd key in
/// availableOptions before they'd otherwise only surface at runtime.
struct ToolDefinitionDecodingTests {

    private static var registryDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ImageSherpaTests/
            .deletingLastPathComponent()   // project root
            .appendingPathComponent("ImageSherpa/Registry")
    }

    private static let toolIDs = ["osxphotos", "imagemagick", "ffmpeg", "exiftool"]

    @Test(arguments: toolIDs)
    func decodesEachBundledRegistryFile(toolID: String) throws {
        let url = Self.registryDirectory.appendingPathComponent("\(toolID).json")
        let data = try Data(contentsOf: url)
        let tool = try JSONDecoder().decode(ToolDefinition.self, from: data)

        #expect(tool.id == toolID)
        #expect(!tool.recipes.isEmpty)
    }

    @Test(arguments: toolIDs)
    func availableOptionsHaveNoDuplicateFlags(toolID: String) throws {
        let url = Self.registryDirectory.appendingPathComponent("\(toolID).json")
        let data = try Data(contentsOf: url)
        let tool = try JSONDecoder().decode(ToolDefinition.self, from: data)

        let flags = (tool.availableOptions ?? []).map(\.flag)
        #expect(Set(flags).count == flags.count)
    }
}
