import SwiftUI

/// Lists a tool's recipes. Tapping one opens RecipeFormView, per CLAUDE.md's build order.
struct ToolDetailView: View {
    let tool: ToolDefinition

    var body: some View {
        List(tool.recipes) { recipe in
            NavigationLink(value: recipe) {
                VStack(alignment: .leading) {
                    Text(recipe.label).font(.headline)
                    Text(recipe.description).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(tool.displayName)
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeFormView(recipe: recipe)
        }
    }
}
