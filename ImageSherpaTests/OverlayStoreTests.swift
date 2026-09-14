import Testing
@testable import ImageSherpa

struct OverlayStoreTests {

    private func recipe(_ id: String, label: String = "") -> Recipe {
        Recipe(id: id, label: label.isEmpty ? id : label, description: "", template: "echo {x}", fields: [])
    }

    @Test func mergeAppendsCustomRecipes() {
        let bundled = [recipe("a"), recipe("b")]
        var overlay = RecipeOverlay()
        overlay.addedOrEditedRecipes = [recipe("custom")]

        let merged = OverlayStore.mergedRecipes(bundled: bundled, overlay: overlay)

        #expect(merged.map(\.id) == ["a", "b", "custom"])
    }

    @Test func mergeOverridesBundledRecipeWithMatchingID() {
        let bundled = [recipe("a", label: "Original")]
        var overlay = RecipeOverlay()
        overlay.addedOrEditedRecipes = [recipe("a", label: "Edited")]

        let merged = OverlayStore.mergedRecipes(bundled: bundled, overlay: overlay)

        #expect(merged.count == 1)
        #expect(merged[0].label == "Edited")
    }

    @Test func mergeFiltersHiddenRecipeIDs() {
        let bundled = [recipe("a"), recipe("b")]
        var overlay = RecipeOverlay()
        overlay.hiddenRecipeIDs = ["a"]

        let merged = OverlayStore.mergedRecipes(bundled: bundled, overlay: overlay)

        #expect(merged.map(\.id) == ["b"])
    }

    @Test func mergeHidesEditedBundledRecipeIfAlsoHidden() {
        let bundled = [recipe("a", label: "Original")]
        var overlay = RecipeOverlay()
        overlay.addedOrEditedRecipes = [recipe("a", label: "Edited")]
        overlay.hiddenRecipeIDs = ["a"]

        let merged = OverlayStore.mergedRecipes(bundled: bundled, overlay: overlay)

        #expect(merged.isEmpty)
    }
}
