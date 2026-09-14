import SwiftUI

/// Lists a tool's recipes — bundled ones plus anything layered in via OverlayStore.
/// Tapping one opens RecipeFormView; the "+" toolbar item and each row's context menu
/// open RecipeEditorView to add/edit/remove (see #11).
struct ToolDetailView: View {
    let tool: ToolDefinition

    @State private var recipes: [Recipe] = []
    @State private var editingRecipe: EditTarget?

    private enum EditTarget: Identifiable {
        case new
        case existing(Recipe)

        var id: String {
            switch self {
            case .new: return "__new__"
            case .existing(let recipe): return recipe.id
            }
        }

        var recipe: Recipe? {
            if case .existing(let recipe) = self { return recipe }
            return nil
        }
    }

    var body: some View {
        List(recipes) { recipe in
            NavigationLink(value: recipe) {
                VStack(alignment: .leading) {
                    Text(recipe.label).font(.headline)
                    Text(recipe.description).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .contextMenu {
                Button("Edit") { editingRecipe = .existing(recipe) }
                Button("Remove", role: .destructive) { remove(recipe) }
            }
        }
        .navigationTitle(tool.displayName)
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeFormView(recipe: recipe)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    editingRecipe = .new
                } label: {
                    Label("New Recipe", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingRecipe) { target in
            NavigationStack {
                RecipeEditorView(tool: tool, existingRecipe: target.recipe, onSave: reload)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        recipes = OverlayStore.recipes(for: tool)
    }

    private func remove(_ recipe: Recipe) {
        try? OverlayStore.remove(recipeID: recipe.id, for: tool)
        reload()
    }
}
