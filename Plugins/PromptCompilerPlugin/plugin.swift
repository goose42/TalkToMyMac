import Foundation
import PackagePlugin

/// Compiles the target's `Prompts/*.md` files into a generated `PromptLibrary.swift`, so
/// editing a prompt's Markdown rebuilds the app with the new text. `Prompts/README.md` is
/// documentation, not a prompt, and is skipped.
@main
struct PromptCompilerPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let promptsDirectory = target.directoryURL.appendingPathComponent("Prompts")
        let prompts = try FileManager.default
            .contentsOfDirectory(at: promptsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && $0.lastPathComponent.lowercased() != "readme.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("PromptLibrary.swift")
        return [
            .buildCommand(
                displayName: "Compiling \(prompts.count) prompts",
                executable: try context.tool(named: "PromptCompiler").url,
                arguments: [output.path] + prompts.map(\.path),
                inputFiles: prompts,
                outputFiles: [output]
            ),
        ]
    }
}
