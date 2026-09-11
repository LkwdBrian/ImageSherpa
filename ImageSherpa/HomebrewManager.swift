import Foundation

/// Install/uninstall/version-check for Homebrew formulae. Everything in the Recipe UI
/// assumes a tool is installed via this manager first, so this is the foundation the
/// rest of the app builds on.
enum HomebrewManager {

    enum BrewPath {
        /// Homebrew installs to different prefixes on Apple Silicon vs Intel; check both
        /// rather than relying on the login shell's PATH, since GUI apps don't inherit it.
        static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

        static func resolved() -> String? {
            candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
    }

    struct FormulaStatus {
        let isInstalled: Bool
        let installedVersion: String?
    }

    static func isHomebrewInstalled() -> Bool {
        BrewPath.resolved() != nil
    }

    /// Parses `brew list --versions <formula>` output directly rather than the registry's
    /// versionRegex/versionCommand fields; this is more reliable for most formulae.
    /// See CLAUDE.md's Framework Reality Checks — the regex path stays as a documented
    /// fallback, not wired in here.
    static func status(forFormula formula: String) async -> FormulaStatus {
        guard let brew = BrewPath.resolved() else {
            return FormulaStatus(isInstalled: false, installedVersion: nil)
        }
        let output = await run(brew, arguments: ["list", "--versions", formula])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return FormulaStatus(isInstalled: false, installedVersion: nil)
        }
        // Output looks like "formula 1.2.3" (or multiple versions space-separated).
        let parts = trimmed.split(separator: " ")
        let version = parts.count > 1 ? String(parts[1]) : nil
        return FormulaStatus(isInstalled: true, installedVersion: version)
    }

    static func install(formula: String, onOutput: @escaping (String) -> Void) async -> Int32 {
        await runStreaming(arguments: ["install", formula], onOutput: onOutput)
    }

    static func uninstall(formula: String, onOutput: @escaping (String) -> Void) async -> Int32 {
        await runStreaming(arguments: ["uninstall", formula], onOutput: onOutput)
    }

    private static func runStreaming(
        arguments: [String],
        onOutput: @escaping (String) -> Void
    ) async -> Int32 {
        guard let brew = BrewPath.resolved() else {
            onOutput("Homebrew not found at \(BrewPath.candidates.joined(separator: " or ")).")
            return -1
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = arguments

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
                DispatchQueue.main.async { onOutput("Failed to launch brew: \(error.localizedDescription)") }
                continuation.resume(returning: -1)
            }
        }
    }

    private static func run(_ executablePath: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
