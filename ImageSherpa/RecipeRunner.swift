import Foundation
#if canImport(Darwin)
import Darwin
#endif

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

    /// A login shell (`-l`) sources `~/.zprofile`, not `~/.zshrc` — only an *interactive*
    /// shell sources `.zshrc`. If a tool's install location was added to PATH via a line in
    /// `.zshrc` (as pipx's `ensurepath` commonly does, adding `~/.local/bin`), a plain `-l`
    /// subprocess never picks it up, and the command silently becomes "command not found" —
    /// which looks nothing like a permission problem, and is easy to mistake for one (see
    /// CLAUDE.md's Framework Reality Checks). Rather than depend on the user's shell dotfiles
    /// at all, explicitly prepend the known install locations every recipe/optionsCommand
    /// might need, the same way HomebrewManager/PipxManager resolve their own binaries by
    /// explicit path instead of trusting shell PATH resolution.
    private static func withGuaranteedPath(_ command: String) -> String {
        "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; " + command
    }

    /// Result of resolving a folder-based recipe's affected-file preview (#16).
    struct FolderPreview {
        let fileNames: [String]
        let displayPath: String
        let folderExists: Bool
        var count: Int { fileNames.count }
    }

    /// Resolves which files a folder-type field's glob will match, purely via FileManager
    /// — no dry-run support from the underlying CLI is needed, since the glob itself is
    /// already known from the recipe template (or an explicit previewGlob override).
    /// Non-recursive: matches the actual shell glob (`{sourceFolder}/*`) and exiftool's own
    /// default (every file directly in the folder, no subdirectories).
    static func folderPreview(for recipe: Recipe, folderField: RecipeField, values: [String: String]) -> FolderPreview? {
        let rawPath = values[folderField.name] ?? folderField.default ?? ""
        guard !rawPath.isEmpty else { return nil }

        let expandedPath = (rawPath as NSString).expandingTildeInPath
        let glob = resolvedGlob(for: recipe, folderFieldName: folderField.name, values: values)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return FolderPreview(fileNames: [], displayPath: rawPath, folderExists: false)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: expandedPath)) ?? []
        // FNM_PERIOD makes "*" behave like an actual shell glob (which doesn't match
        // leading-dot files, e.g. .DS_Store, unless the pattern itself starts with a dot)
        // — matches what {sourceFolder}/* actually expands to in the imagemagick recipes'
        // for-loops. FNM_CASEFOLD mirrors the `nocaseglob` those same for-loops set (and
        // exiftool's own case-insensitive -ext matching), so e.g. "IMG_1.JPG" previews the
        // same as it will actually be processed. fnmatch itself has no concept of shell
        // brace alternation ("*.{jpg,png}"), unlike the zsh for-loops that actually run the
        // command, so that has to be expanded into separate patterns first.
        let patterns = expandBraceAlternatives(glob)
        let matches = contents.filter { name in
            patterns.contains { fnmatch($0, name, FNM_PERIOD | FNM_CASEFOLD) == 0 }
        }.sorted()
        return FolderPreview(fileNames: matches, displayPath: rawPath, folderExists: true)
    }

    /// Prefers an explicit `previewGlob` override; otherwise derives the glob from
    /// whatever immediately follows `{folderFieldName}` in the template up to the next
    /// whitespace/quote (e.g. "/*" or "/*.{extension}"), defaulting to "*" when the field
    /// appears bare (exiftool's recipes, which pass the folder straight through with no
    /// shell glob at all). Any other {field} placeholders inside the resolved glob (e.g.
    /// "{extension}") are substituted with the form's current values, same as buildCommand.
    private static func resolvedGlob(for recipe: Recipe, folderFieldName: String, values: [String: String]) -> String {
        var glob = recipe.previewGlob ?? derivedGlobSuffix(template: recipe.template, folderFieldName: folderFieldName) ?? "*"

        for field in recipe.fields {
            let token = "{\(field.name)}"
            guard glob.contains(token) else { continue }
            let value = values[field.name]
            let resolvedValue = (value?.isEmpty == false) ? value! : (field.default ?? "")
            glob = glob.replacingOccurrences(of: token, with: resolvedValue)
        }
        return glob
    }

    /// Expands a single shell brace group ("*.{jpg,png}" -> ["*.jpg", "*.png"]) since
    /// fnmatch, unlike the zsh for-loops that actually run the command, has no concept of
    /// brace alternation. Only one group is ever used in practice (an extension list), so
    /// nested/multiple groups aren't handled.
    private static func expandBraceAlternatives(_ pattern: String) -> [String] {
        guard let openBrace = pattern.firstIndex(of: "{"),
              let closeBrace = pattern[openBrace...].firstIndex(of: "}") else {
            return [pattern]
        }
        let prefix = pattern[pattern.startIndex..<openBrace]
        let suffix = pattern[pattern.index(after: closeBrace)...]
        let alternatives = pattern[pattern.index(after: openBrace)..<closeBrace].split(separator: ",", omittingEmptySubsequences: false)
        return alternatives.map { "\(prefix)\($0)\(suffix)" }
    }

    private static func derivedGlobSuffix(template: String, folderFieldName: String) -> String? {
        let token = "{\(folderFieldName)}"
        guard let tokenRange = template.range(of: token) else { return nil }
        let rest = template[tokenRange.upperBound...]
        guard rest.hasPrefix("/") else { return "*" }

        let suffix = String(rest.dropFirst())
        // Stop at whitespace/quotes, or shell metacharacters that can immediately follow a
        // glob with no separating space (e.g. "{sourceFolder}/*; do ..." in the batch
        // imagemagick recipes' for-loops).
        let terminators: Set<Character> = [" ", "\"", "'", ";", "&", "|", "(", ")", "\n", "\t"]
        let glob = String(suffix.prefix { !terminators.contains($0) })
        return glob.isEmpty ? "*" : glob
    }

    /// Result of resolving an osxphotos recipe's thumbnail preview (#17) by running its
    /// `previewQuery` read-only equivalent instead of actually exporting.
    enum PhotoPreviewResult {
        case success([String])
        case fullDiskAccessNeeded
        case failure(String)
    }

    /// Runs `recipe.previewQuery` (with the same {fieldName} substitution as buildCommand)
    /// and extracts the `path` of every matching photo from its `--json` output, so
    /// RecipeFormView can show a thumbnail grid before the user commits to the actual
    /// export. `path` is osxphotos's on-disk original path; it's `null` for photos not
    /// downloaded locally (iCloud-only originals), so those are filtered out here rather
    /// than passed on as unloadable thumbnails.
    static func photoPreview(for recipe: Recipe, values: [String: String]) async -> PhotoPreviewResult {
        guard let queryTemplate = recipe.previewQuery else {
            return .failure("No preview available for this recipe.")
        }

        var command = queryTemplate
        for field in recipe.fields {
            let token = "{\(field.name)}"
            guard command.contains(token) else { continue }
            let rawValue = values[field.name] ?? field.default ?? ""
            guard !rawValue.isEmpty else {
                return .failure("Fill in \"\(field.label)\" to preview matching photos.")
            }
            let needsQuoting = [RecipeField.FieldType.folder, .file, .quotedText, .choice, .dynamicChoice].contains(field.type)
            let safeValue = needsQuoting ? "\"\(rawValue)\"" : rawValue
            command = command.replacingOccurrences(of: token, with: safeValue)
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", withGuaranteedPath(command)]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            // Drain both pipes concurrently while the process runs, not after it exits.
            // osxphotos --json output includes full per-photo metadata (EXIF, place, album
            // membership, ...) and can exceed the ~64KB kernel pipe buffer for even a small
            // album. Reading only in terminationHandler (as buildCommand's caller does
            // elsewhere) deadlocks in that case: the child blocks on write() waiting for the
            // pipe to drain, while we block on the process exiting before we read — neither
            // side ever proceeds, and the preview spins forever instead of erroring.
            let readQueue = DispatchQueue(label: "photoPreview.pipeReader")
            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            readQueue.async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            readQueue.async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.terminationHandler = { proc in
                group.wait()
                let photos = (try? JSONSerialization.jsonObject(with: outData)) as? [[String: Any]]

                guard proc.terminationStatus == 0, let photos else {
                    let errText = String(data: errData, encoding: .utf8) ?? ""
                    let result: PhotoPreviewResult = PermissionHelp.looksLikeFullDiskAccessDenial(errText)
                        ? .fullDiskAccessNeeded
                        : .failure("Couldn't run the preview query.")
                    continuation.resume(returning: result)
                    return
                }

                let paths = photos.compactMap { $0["path"] as? String }
                    .filter { FileManager.default.fileExists(atPath: $0) }
                continuation.resume(returning: .success(paths))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure("Failed to launch: \(error.localizedDescription)"))
            }
        }
    }

    enum OptionsLoadResult {
        case success([String])
        case fullDiskAccessNeeded
        case failure
    }

    /// Runs a dynamic_choice field's optionsCommand and returns its stdout split into
    /// non-blank lines, one per option. Stderr is captured (not mixed into the options
    /// list — noise there would show up as bogus picker entries) only to check whether the
    /// failure looks like a Full Disk Access denial, so the form can point at the fix
    /// instead of a generic "couldn't load options" message. Never throws; callers fall
    /// back to a plain text field on any failure per the "never block the form" rule.
    static func runOptionsCommand(_ command: String) async -> OptionsLoadResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", withGuaranteedPath(command)]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

                guard proc.terminationStatus == 0, !lines.isEmpty else {
                    // optionsCommand is typically a pipeline (e.g. "osxphotos albums | awk
                    // ..."), so terminationStatus reflects the last stage (awk), not
                    // osxphotos — a crashing upstream command still exits the pipeline 0
                    // with empty output. Always check stderr here, not just on a nonzero
                    // exit, or a real failure disguised as an empty success would never get
                    // classified as a Full Disk Access denial.
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8) ?? ""
                    let result: OptionsLoadResult = PermissionHelp.looksLikeFullDiskAccessDenial(errText)
                        ? .fullDiskAccessNeeded : .failure
                    continuation.resume(returning: result)
                    return
                }
                continuation.resume(returning: .success(lines))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure)
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
            process.arguments = ["-l", "-c", withGuaranteedPath(command)]  // -l loads the login profile; withGuaranteedPath covers what -l alone misses (see its doc comment)

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
