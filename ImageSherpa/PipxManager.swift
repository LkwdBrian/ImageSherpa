import Foundation

/// Install/uninstall/version-check for pipx-managed Python CLI tools (e.g. osxphotos,
/// which has no Homebrew formula — see issue #18). Parallel to HomebrewManager per
/// CLAUDE.md's Framework Reality Checks: pip-only tools get their own manager rather than
/// overloading HomebrewManager's brew-specific logic.
enum PipxManager {

    enum PipxPath {
        /// pipx commonly lands in one of these depending on how it itself was installed
        /// (`brew install pipx`, or `python3 -m pip install --user pipx`). GUI apps don't
        /// inherit the login shell's PATH, so check known locations directly rather than
        /// relying on `which`, matching HomebrewManager's approach.
        static let candidates = [
            "/opt/homebrew/bin/pipx",
            "/usr/local/bin/pipx",
            NSHomeDirectory() + "/.local/bin/pipx"
        ]

        static func resolved() -> String? {
            candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
    }

    static func isPipxInstalled() -> Bool {
        PipxPath.resolved() != nil
    }

    /// Parses `pipx list --json` rather than shelling out per-package, since pipx has no
    /// single-package status subcommand. Uses JSONSerialization (Foundation, no added
    /// dependency) since this is a one-off ad hoc shape, not worth a Codable model.
    static func status(forFormula package: String) async -> PackageStatus {
        guard let pipx = PipxPath.resolved() else {
            return PackageStatus(isInstalled: false, installedVersion: nil)
        }
        let output = await run(pipx, arguments: ["list", "--json"])
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let venvs = json["venvs"] as? [String: Any],
            let entry = venvs[package] as? [String: Any],
            let metadata = entry["metadata"] as? [String: Any],
            let mainPackage = metadata["main_package"] as? [String: Any],
            let version = mainPackage["package_version"] as? String
        else {
            return PackageStatus(isInstalled: false, installedVersion: nil)
        }
        return PackageStatus(isInstalled: true, installedVersion: version)
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
        guard let pipx = PipxPath.resolved() else {
            onOutput("pipx not found at \(PipxPath.candidates.joined(separator: " or ")). Install it with `brew install pipx` first.")
            return -1
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pipx)
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
                DispatchQueue.main.async { onOutput("Failed to launch pipx: \(error.localizedDescription)") }
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
