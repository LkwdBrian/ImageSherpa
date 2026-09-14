import Foundation

/// Takes a Recipe + the user's filled-in field values, builds the final shell command,
/// and executes it via /bin/zsh so PATH-based lookups (brew-installed binaries) resolve
/// the same way they would in Terminal.
final class RecipeRunner {

    enum RunnerError: LocalizedError {
        case missingField(String)
        case missingBundledScripts
        var errorDescription: String? {
            switch self {
            case .missingField(let name):
                return "Missing required value for \"\(name)\"."
            case .missingBundledScripts:
                return "Couldn't locate the app's bundled Scripts folder. Reinstalling the app may fix this."
            }
        }
    }

    /// Substitutes {fieldName} tokens in the template with user-provided values.
    /// Returns the final command string for preview (shown to the user before running,
    /// per the "teach, don't just black-box it" goal) and for execution.
    ///
    /// Also resolves the built-in {scriptsDir} token, used by recipes that call into
    /// bundled Python query-function scripts (see Scripts/photo_scoring.py). This token
    /// isn't a RecipeField the user fills in; it's always resolved by the app itself.
    static func buildCommand(from recipe: Recipe, values: [String: String]) throws -> String {
        var command = recipe.template

        if command.contains("{scriptsDir}") {
            guard let scriptsDir = bundledScriptsDirectory() else {
                throw RunnerError.missingBundledScripts
            }
            command = command.replacingOccurrences(of: "{scriptsDir}", with: "\"\(scriptsDir)\"")
        }

        for field in recipe.fields {
            let token = "{\(field.name)}"
            guard command.contains(token) else { continue }
            let rawValue = values[field.name] ?? field.default ?? ""
            guard !rawValue.isEmpty else {
                throw RunnerError.missingField(field.label)
            }
            // Quote path-like and free-text values defensively (city names, person names,
            // keywords, folder paths can all contain spaces). Leave bare "text" tokens
            // (widths, percentages, extensions, dates) unquoted so glob patterns like
            // *.jpg still expand correctly and numeric values pass through cleanly.
            let needsQuoting = [RecipeField.FieldType.folder, .file, .quotedText, .choice, .dynamicChoice].contains(field.type)
            let safeValue = needsQuoting ? "\"\(rawValue)\"" : rawValue
            command = command.replacingOccurrences(of: token, with: safeValue)
        }
        return command
    }

    /// Scripts/ is a source-only grouping folder; Xcode's file-system-synchronized
    /// groups flatten it on copy, so bundled scripts land directly in the app's
    /// top-level Resources directory at runtime (see ToolRegistryLoader for the
    /// same caveat on Registry/).
    private static func bundledScriptsDirectory() -> String? {
        Bundle.main.resourceURL?.path
    }

    /// Runs a dynamic_choice field's optionsCommand and returns its stdout split into
    /// non-blank lines, one per option. Stderr is discarded rather than mixed in, since
    /// noise there (warnings, progress) would otherwise show up as bogus picker entries.
    /// Returns nil on any failure (non-zero exit, launch failure) so callers can fall back
    /// to a plain text field per the "never block the form" rule.
    static func runOptionsCommand(_ command: String) async -> [String]? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()   // discarded

            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                continuation.resume(returning: lines.isEmpty ? nil : lines)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Runs the built command, streaming stdout/stderr lines to the handler as they arrive.
    static func execute(
        command: String,
        onOutput: @escaping (String) -> Void
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]  // -l loads the login profile so brew's PATH is present

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { onOutput(text) }
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { onOutput("Failed to launch: \(error.localizedDescription)") }
                continuation.resume(returning: -1)
            }
        }
    }
}
