import Foundation

/// Per-tool user customizations layered on top of a bundled Registry/*.json's recipes.
/// Bundled JSON stays read-only (it's inside the app bundle and gets flattened into
/// Resources at build time — there's no way to write to it at runtime), so anything a
/// user adds or edits lives here instead, at
/// `~/Library/Application Support/ImageSherpa/Overlays/<toolId>.json`, which survives
/// app rebuilds/updates by construction.
///
/// A bundled recipe can't be truly deleted (it ships in the app), so removing one is
/// really hiding it via `hiddenRecipeIDs` — the UI says "Remove", not "Delete forever",
/// to be upfront about that distinction.
struct RecipeOverlay: Codable {
    var addedOrEditedRecipes: [Recipe] = []
    var hiddenRecipeIDs: [String] = []
}

enum OverlayStore {
    private static var overlaysDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ImageSherpa/Overlays", isDirectory: true)
    }

    private static func overlayURL(for toolID: String) -> URL {
        overlaysDirectory.appendingPathComponent("\(toolID).json")
    }

    /// Per-tool files (not one big overlay.json) so a corrupt file only affects one
    /// tool's recipes, not every tool's at once. A missing or corrupt file is treated
    /// as "no customizations yet" rather than an error.
    static func load(for toolID: String) -> RecipeOverlay {
        let url = overlayURL(for: toolID)
        guard let data = try? Data(contentsOf: url),
              let overlay = try? JSONDecoder().decode(RecipeOverlay.self, from: data) else {
            return RecipeOverlay()
        }
        return overlay
    }

    static func save(_ overlay: RecipeOverlay, for toolID: String) throws {
        try FileManager.default.createDirectory(at: overlaysDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(overlay)
        try data.write(to: overlayURL(for: toolID), options: .atomic)
    }

    /// Merges a tool's bundled recipes with its overlay: an overlay recipe whose id
    /// matches a bundled one overrides it (edit), a new id is appended (custom recipe),
    /// and anything in hiddenRecipeIDs is filtered out of the result.
    static func mergedRecipes(bundled: [Recipe], overlay: RecipeOverlay) -> [Recipe] {
        var byID: [String: Recipe] = [:]
        var order: [String] = []
        for recipe in bundled {
            byID[recipe.id] = recipe
            order.append(recipe.id)
        }
        for recipe in overlay.addedOrEditedRecipes {
            if byID[recipe.id] == nil {
                order.append(recipe.id)
            }
            byID[recipe.id] = recipe
        }
        return order.compactMap { byID[$0] }.filter { !overlay.hiddenRecipeIDs.contains($0.id) }
    }

    static func recipes(for tool: ToolDefinition) -> [Recipe] {
        mergedRecipes(bundled: tool.recipes, overlay: load(for: tool.id))
    }

    /// Adds a new recipe or overwrites an edited one. If this id was previously hidden
    /// (the user removed a stock recipe, then re-added/edited one with the same id),
    /// un-hide it — an explicit save should always make the recipe visible again.
    static func upsert(_ recipe: Recipe, for toolID: String) throws {
        var overlay = load(for: toolID)
        overlay.addedOrEditedRecipes.removeAll { $0.id == recipe.id }
        overlay.addedOrEditedRecipes.append(recipe)
        overlay.hiddenRecipeIDs.removeAll { $0 == recipe.id }
        try save(overlay, for: toolID)
    }

    /// Removes a recipe from the tool's list. A custom (overlay-only) recipe is deleted
    /// outright; a bundled recipe is hidden instead, since it ships in the app and can't
    /// actually be deleted from disk.
    static func remove(recipeID: String, for tool: ToolDefinition) throws {
        var overlay = load(for: tool.id)
        let isBundled = tool.recipes.contains { $0.id == recipeID }
        overlay.addedOrEditedRecipes.removeAll { $0.id == recipeID }
        if isBundled && !overlay.hiddenRecipeIDs.contains(recipeID) {
            overlay.hiddenRecipeIDs.append(recipeID)
        }
        try save(overlay, for: tool.id)
    }
}
