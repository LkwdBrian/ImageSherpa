import Foundation

/// Install status shared by every install-method-specific manager (HomebrewManager,
/// PipxManager, ...) so callers like DependenciesView don't need to branch on which
/// manager produced it.
struct PackageStatus {
    let isInstalled: Bool
    let installedVersion: String?
}

/// Dispatches install/uninstall/status calls to the right manager based on
/// ToolDefinition.installMethod, so DependenciesView doesn't need to know which tools use
/// which install method. installMethod stays a plain String on ToolDefinition (see
/// CLAUDE.md's Non-Negotiables) so adding a new method here is a code change, but adding a
/// new *tool* using an existing method never is.
enum PackageManagerRouter {
    static func isAvailable(for installMethod: String) -> Bool {
        switch installMethod {
        case "brew": return HomebrewManager.isHomebrewInstalled()
        case "pipx": return PipxManager.isPipxInstalled()
        default: return false
        }
    }

    static func status(for tool: ToolDefinition) async -> PackageStatus {
        switch tool.installMethod {
        case "brew": return await HomebrewManager.status(forFormula: tool.formula)
        case "pipx": return await PipxManager.status(forFormula: tool.formula)
        default: return PackageStatus(isInstalled: false, installedVersion: nil)
        }
    }

    static func install(tool: ToolDefinition, onOutput: @escaping (String) -> Void) async -> Int32 {
        switch tool.installMethod {
        case "brew": return await HomebrewManager.install(formula: tool.formula, onOutput: onOutput)
        case "pipx": return await PipxManager.install(formula: tool.formula, onOutput: onOutput)
        default:
            onOutput("Unknown install method \"\(tool.installMethod)\".")
            return -1
        }
    }

    static func uninstall(tool: ToolDefinition, onOutput: @escaping (String) -> Void) async -> Int32 {
        switch tool.installMethod {
        case "brew": return await HomebrewManager.uninstall(formula: tool.formula, onOutput: onOutput)
        case "pipx": return await PipxManager.uninstall(formula: tool.formula, onOutput: onOutput)
        default:
            onOutput("Unknown install method \"\(tool.installMethod)\".")
            return -1
        }
    }
}
