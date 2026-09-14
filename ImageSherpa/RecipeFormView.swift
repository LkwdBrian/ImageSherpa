import SwiftUI

private struct RunLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let command: String
    var output: String
    var exitCode: Int32?
}

/// Generates a form from Recipe.fields, shows a live command preview (always visible
/// before running, per CLAUDE.md's "show the real command" non-negotiable), and runs it
/// via RecipeRunner while streaming output into a run log.
struct RecipeFormView: View {
    let recipe: Recipe

    @State private var values: [String: String] = [:]
    @State private var preview: String = ""
    @State private var previewError: String?
    @State private var isRunning = false
    @State private var log: [RunLogEntry] = []
    @State private var dynamicOptions: [String: [String]] = [:]
    @State private var dynamicOptionsFailed: Set<String> = []
    @State private var loadingOptions: Set<String> = []

    var body: some View {
        Form {
            Section(recipe.label) {
                Text(recipe.description).foregroundStyle(.secondary)

                ForEach(recipe.fields) { field in
                    fieldRow(for: field)
                }
            }

            Section("Command Preview") {
                if let previewError {
                    Label(previewError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Button {
                    Task { await run() }
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Run")
                    }
                }
                .disabled(isRunning || previewError != nil)
            }

            if !log.isEmpty {
                Section("Run Log") {
                    ForEach(log.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.command)
                                .font(.system(.caption, design: .monospaced))
                            if !entry.output.isEmpty {
                                Text(entry.output)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if let exitCode = entry.exitCode, exitCode != 0 {
                                Text("Exited with status \(exitCode)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(recipe.label)
        .onAppear(perform: seedDefaults)
        .onChange(of: values) { _, _ in updatePreview() }
    }

    @ViewBuilder
    private func fieldRow(for field: RecipeField) -> some View {
        switch field.type {
        case .text, .quotedText:
            TextField(field.label, text: binding(for: field))
        case .folder, .file:
            HStack {
                TextField(field.label, text: binding(for: field))
                Button("Choose…") {
                    if let path = FolderPicker.choose(canChooseFiles: field.type == .file) {
                        values[field.name] = path
                    }
                }
            }
        case .choice:
            Picker(field.label, selection: binding(for: field)) {
                Text("Select…").tag("")
                ForEach(field.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        case .dynamicChoice:
            dynamicChoiceRow(for: field)
        }
    }

    @ViewBuilder
    private func dynamicChoiceRow(for field: RecipeField) -> some View {
        if loadingOptions.contains(field.name) {
            HStack {
                Text(field.label)
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else if dynamicOptionsFailed.contains(field.name) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Couldn't load options automatically — enter a value manually.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    // Without an explicit layoutPriority, the Button's compression
                    // resistance beats the TextField's in a tight HStack and squeezes it
                    // down to a sliver — it renders, but looks like there's no text field
                    // at all next to "Retry".
                    TextField(field.label, text: binding(for: field))
                        .layoutPriority(1)
                    Button("Retry") { Task { await loadOptions(for: field) } }
                }
            }
        } else {
            HStack {
                Picker(field.label, selection: binding(for: field)) {
                    Text("Select…").tag("")
                    ForEach(dynamicOptions[field.name] ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                Button {
                    Task { await loadOptions(for: field) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload options")
            }
        }
    }

    private func binding(for field: RecipeField) -> Binding<String> {
        Binding(
            get: { values[field.name] ?? "" },
            set: { values[field.name] = $0 }
        )
    }

    private func seedDefaults() {
        for field in recipe.fields {
            values[field.name] = field.default ?? ""
        }
        updatePreview()

        for field in recipe.fields where field.type == .dynamicChoice {
            Task { await loadOptions(for: field) }
        }
    }

    /// Loads a dynamic_choice field's options once per form session (not re-run per
    /// keystroke) since the underlying data (e.g. Photos albums) rarely changes mid-session;
    /// the picker's reload button covers the case where it does.
    private func loadOptions(for field: RecipeField) async {
        guard let command = field.optionsCommand else { return }
        dynamicOptionsFailed.remove(field.name)
        loadingOptions.insert(field.name)
        defer { loadingOptions.remove(field.name) }

        if let options = await RecipeRunner.runOptionsCommand(command) {
            dynamicOptions[field.name] = options
        } else {
            dynamicOptionsFailed.insert(field.name)
        }
    }

    private func updatePreview() {
        do {
            preview = try RecipeRunner.buildCommand(from: recipe, values: values)
            previewError = nil
        } catch {
            preview = ""
            previewError = error.localizedDescription
        }
    }

    private func run() async {
        guard previewError == nil else { return }
        isRunning = true
        defer { isRunning = false }

        log.append(RunLogEntry(timestamp: Date(), command: preview, output: ""))
        let index = log.count - 1

        let exitCode = await RecipeRunner.execute(command: preview) { chunk in
            log[index].output += chunk
        }
        log[index].exitCode = exitCode
    }
}
