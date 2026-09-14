import Foundation

/// Decodes a single tool registry JSON file (e.g. osxphotos.json, imagemagick.json).
/// Drop new JSON files into the Registry/ folder to add support for more CLI tools
/// without touching any Swift code.
struct ToolDefinition: Codable, Identifiable {
    let id: String
    let displayName: String
    let summary: String
    let installMethod: String   // currently only "brew" is handled; leaves room for "pip", "npm", "cargo" later
    let formula: String
    let homepage: String
    let versionCommand: String
    let versionRegex: String
    let recipes: [Recipe]
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let description: String
    let template: String        // command string with {fieldName} placeholders
    let fields: [RecipeField]
}

struct RecipeField: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let label: String
    let type: FieldType
    let `default`: String?
    let options: [String]?          // choice: fixed list of selectable values
    let optionsCommand: String?     // dynamic_choice: shell command whose stdout (one option per line) populates the picker

    init(name: String, label: String, type: FieldType, default: String? = nil, options: [String]? = nil, optionsCommand: String? = nil) {
        self.name = name
        self.label = label
        self.type = type
        self.default = `default`
        self.options = options
        self.optionsCommand = optionsCommand
    }

    enum FieldType: String, Codable, Hashable {
        case text          // short values with no spaces expected: numbers, extensions, dates
        case quotedText = "quoted_text"   // free-text values that may contain spaces: names, keywords, cities
        case folder
        case file
        case choice          // fixed set of options known ahead of time, no shell-out
        case dynamicChoice = "dynamic_choice"   // options populated by running optionsCommand
    }
}

/// Loads every registry .json file bundled with the app.
///
/// Source files live under `Registry/` for developer organization, but Xcode's
/// file-system-synchronized groups flatten subfolders when copying resources, so at
/// runtime every .json file lands directly in `Bundle.main.resourceURL`, not in a
/// "Registry" subdirectory. Decoding failures (e.g. a non-registry .json slipping into
/// the bundle) are treated as "not a registry file" rather than a fatal error.
enum ToolRegistryLoader {
    static func loadAll() -> [ToolDefinition] {
        guard let resourceURL = Bundle.main.resourceURL else {
            return []
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resourceURL, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) else {
            return []
        }

        let decoder = JSONDecoder()
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ToolDefinition.self, from: data)
        }
        .sorted { $0.displayName < $1.displayName }
    }
}
