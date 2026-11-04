// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TalkToMyMac",
    platforms: [.macOS("26.0")],
    products: [
        // Exposed so the standalone eval harness in `evals/` can use the app's prompts,
        // dictionary cleanup and generation settings.
        .library(name: "TalkToMyMacCore", targets: ["TalkToMyMacCore"]),
    ],
    dependencies: [
        // Runs the Parakeet speech-to-text Core ML model on-device.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        // Core library — pure logic, fully testable, no macOS UI dependencies
        .target(
            name: "TalkToMyMacCore",
            path: "Sources/TalkToMyMacCore",
            // The Markdown prompts are compiled into `PromptLibrary` by the plugin below.
            exclude: ["Prompts"],
            plugins: ["PromptCompilerPlugin"]
        ),

        // Prompt Markdown → Swift source. Pure logic, shared by the tool and its tests.
        .target(
            name: "PromptCodegen",
            path: "Sources/PromptCodegen"
        ),
        .executableTarget(
            name: "PromptCompiler",
            dependencies: ["PromptCodegen"],
            path: "Sources/PromptCompiler"
        ),
        .plugin(
            name: "PromptCompilerPlugin",
            capability: .buildTool(),
            dependencies: ["PromptCompiler"],
            path: "Plugins/PromptCompilerPlugin"
        ),

        // macOS app executable
        .executableTarget(
            name: "TalkToMyMac",
            dependencies: [
                "TalkToMyMacCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/TalkToMyMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Speech"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ApplicationServices"),
                .linkedLibrary("sqlite3"),
            ]
        ),

        // Unit tests for core logic
        .testTarget(
            name: "TalkToMyMacCoreTests",
            dependencies: ["TalkToMyMacCore"],
            path: "Tests/TalkToMyMacCoreTests"
        ),
        .testTarget(
            name: "PromptCodegenTests",
            dependencies: ["PromptCodegen"],
            path: "Tests/PromptCodegenTests"
        ),
    ]
)
