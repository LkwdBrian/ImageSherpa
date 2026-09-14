import SwiftUI

/// Add/edit form for a single recipe, presented as a sheet from ToolDetailView's "+"
/// toolbar item (new recipe) or a row's Edit context menu item (existing recipe).
/// Saves into the tool's OverlayStore file, never the bundled Registry/*.json.
struct RecipeEditorView: View {
    let tool: ToolDefinition
    let existingRecipe: Recipe?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var description: String
    @State private var template: String
    @State private var fields: [FieldDraft]
    @State private var validationError: String?
    @State private var optionSearch = ""

    init(tool: ToolDefinition, existingRecipe: Recipe?, onSave: @escaping () -> Void) {
        self.tool = tool
        self.existingRecipe = existingRecipe
        self.onSave = onSave
        _label = State(initialValue: existingRecipe?.label ?? "")
        _description = State(initialValue: existingRecipe?.description ?? "")
        _template = State(initialValue: existingRecipe?.template ?? "")
        _fields = State(initialValue: (existingRecipe?.fields ?? []).map(FieldDraft.init))
    }

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Label", text: $label)
                TextField("Description", text: $description)
                TextField("Command template", text: $template)
                    .font(.system(.body, design: .monospaced))
                Text("Use {fieldName} placeholders for each field below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Insert a \(tool.displayName) Option") {
                if (tool.availableOptions ?? []).isEmpty {
                    Text("No curated options for \(tool.displayName) yet — build the template manually below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Search options", text: $optionSearch)
                    ForEach(filteredOptions) { option in
                        Button {
                            insert(option)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(option.label).font(.subheadline.bold())
                                    Text(option.flag)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                ForEach($fields) { $field in
                    FieldDraftRow(field: $field) {
                        insertPlaceholder(for: field)
                    }
                }
                .onDelete { fields.remove(atOffsets: $0) }

                Button("Add Field") {
                    fields.append(FieldDraft())
                }
            } header: {
                Text("Fields")
            } footer: {
                Text("For anything not covered by a curated option above: name the field, then tap Insert to drop its {placeholder} into the template. A field does nothing until its placeholder is actually in the template.")
            }

            if let validationError {
                Section {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(label.isEmpty || template.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var filteredOptions: [ToolOption] {
        let options = tool.availableOptions ?? []
        guard !optionSearch.isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(optionSearch)
                || $0.flag.localizedCaseInsensitiveContains(optionSearch)
                || $0.description.localizedCaseInsensitiveContains(optionSearch)
        }
    }

    /// Appends a curated option's text to the template and adds any fields it needs
    /// (skipping ones already present by name, so inserting the same option twice — or
    /// two options that happen to share a field name — doesn't duplicate a field row).
    private func insert(_ option: ToolOption) {
        template = template.isEmpty ? option.insertText : template + " " + option.insertText

        for suggested in option.suggestedFields ?? [] {
            guard !fields.contains(where: { $0.name == suggested.name }) else { continue }
            var draft = FieldDraft()
            draft.name = suggested.name
            draft.label = suggested.label
            draft.type = suggested.type
            draft.optionsText = (suggested.options ?? []).joined(separator: ", ")
            draft.optionsCommand = suggested.optionsCommand ?? ""
            fields.append(draft)
        }
    }

    /// Appends a manually-added field's {placeholder} to the template — the same effect
    /// "Insert a Tool Option" gets for free, but for a field the user typed by hand
    /// instead of picking from the curated list. Without this, a field the user adds sits
    /// unused until they separately go edit the template text to reference it, which
    /// isn't obvious from the form alone.
    private func insertPlaceholder(for field: FieldDraft) {
        guard !field.name.isEmpty else { return }
        let token = "{\(field.name)}"
        guard !template.contains(token) else { return }
        template = template.isEmpty ? token : template + " " + token
    }

    /// Validates the template against RecipeRunner.buildCommand with dummy per-field
    /// values before persisting — catches a typo'd {placeholder} immediately instead of
    /// surfacing it as "missing required value" the first time someone tries to run it.
    private func save() {
        let recipeFields = fields.map { $0.toRecipeField() }
        let id = existingRecipe?.id ?? Self.slug(from: label)
        let recipe = Recipe(id: id, label: label, description: description, template: template, fields: recipeFields)

        let dummyValues = Dictionary(uniqueKeysWithValues: recipeFields.map { ($0.name, dummyValue(for: $0)) })
        do {
            _ = try RecipeRunner.buildCommand(from: recipe, values: dummyValues)
        } catch {
            validationError = error.localizedDescription
            return
        }

        do {
            try OverlayStore.upsert(recipe, for: tool.id)
            onSave()
            dismiss()
        } catch {
            validationError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func dummyValue(for field: RecipeField) -> String {
        if let defaultValue = field.default, !defaultValue.isEmpty {
            return defaultValue
        }
        switch field.type {
        case .choice, .dynamicChoice:
            return field.options?.first ?? "sample"
        case .folder, .file:
            return "/tmp"
        case .text, .quotedText:
            return "sample"
        }
    }

    private static func slug(from label: String) -> String {
        let slug = label.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return slug.isEmpty ? UUID().uuidString : slug
    }
}

/// Editable working copy of a RecipeField — a plain string for the comma-separated
/// choice options and an Identifiable id for List/ForEach, neither of which RecipeField
/// itself needs.
private struct FieldDraft: Identifiable {
    let id = UUID()
    var name: String
    var label: String
    var type: RecipeField.FieldType
    var defaultValue: String
    var optionsText: String       // comma-separated, for .choice
    var optionsCommand: String    // for .dynamicChoice

    init() {
        name = ""
        label = ""
        type = .text
        defaultValue = ""
        optionsText = ""
        optionsCommand = ""
    }

    init(from field: RecipeField) {
        name = field.name
        label = field.label
        type = field.type
        defaultValue = field.default ?? ""
        optionsText = (field.options ?? []).joined(separator: ", ")
        optionsCommand = field.optionsCommand ?? ""
    }

    func toRecipeField() -> RecipeField {
        let options = type == .choice
            ? optionsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : nil
        return RecipeField(
            name: name,
            label: label,
            type: type,
            default: defaultValue.isEmpty ? nil : defaultValue,
            options: options,
            optionsCommand: type == .dynamicChoice && !optionsCommand.isEmpty ? optionsCommand : nil
        )
    }
}

private struct FieldDraftRow: View {
    @Binding var field: FieldDraft
    let onInsertPlaceholder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Field name (used in {placeholder})", text: $field.name)
                TextField("Label", text: $field.label)
                Button("Insert", action: onInsertPlaceholder)
                    .disabled(field.name.isEmpty)
                    .help("Insert {\(field.name)} into the command template")
            }
            Picker("Type", selection: $field.type) {
                Text("Text").tag(RecipeField.FieldType.text)
                Text("Quoted Text").tag(RecipeField.FieldType.quotedText)
                Text("Folder").tag(RecipeField.FieldType.folder)
                Text("File").tag(RecipeField.FieldType.file)
                Text("Choice").tag(RecipeField.FieldType.choice)
                Text("Dynamic Choice").tag(RecipeField.FieldType.dynamicChoice)
            }
            TextField("Default value (optional)", text: $field.defaultValue)
            if field.type == .choice {
                TextField("Options (comma-separated)", text: $field.optionsText)
            }
            if field.type == .dynamicChoice {
                TextField("Options command (shell)", text: $field.optionsCommand)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(.vertical, 4)
    }
}
