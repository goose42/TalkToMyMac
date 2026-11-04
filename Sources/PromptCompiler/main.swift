import Foundation
import PromptCodegen

// Usage: PromptCompiler <output.swift> <prompt.md>...
// Run by PromptCompilerPlugin; writes the `PromptLibrary` enum.
let arguments = CommandLine.arguments.dropFirst()
guard let output = arguments.first else {
    FileHandle.standardError.write(Data("usage: PromptCompiler <output.swift> <prompt.md>...\n".utf8))
    exit(64)
}

do {
    let prompts = try arguments.dropFirst().map { path in
        let url = URL(fileURLWithPath: path)
        let contents = try String(contentsOf: url, encoding: .utf8)
        return (fileName: url.lastPathComponent, text: PromptCodegen.promptText(fromFile: contents))
    }
    let source = try PromptCodegen.checkedSource(prompts: prompts)
    try Data(source.utf8).write(to: URL(fileURLWithPath: output), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("error: PromptCompiler: \(error)\n".utf8))
    exit(1)
}
