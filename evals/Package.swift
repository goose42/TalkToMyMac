// swift-tools-version: 6.1
import PackageDescription

// Standalone eval harness for the formatting prompts. Not part of the app build: run it with
// `make eval SUITE=<name>` or `swift run --package-path evals ttm-eval <cases.jsonl>`.
let package = Package(
    name: "TalkToMyMacEvals",
    platforms: [.macOS("26.0")],
    dependencies: [
        // The app package, for its compiled prompts, dictionary cleanup and generation settings.
        // Named explicitly so the dependency resolves whatever the checkout folder is called.
        .package(name: "TalkToMyMac", path: ".."),
    ],
    targets: [
        // Pure logic: case files, options, scoring, judge replies and reports. Fully tested.
        .target(
            name: "EvalKit",
            dependencies: [
                .product(name: "TalkToMyMacCore", package: "TalkToMyMac"),
                .product(name: "PromptCodegen", package: "TalkToMyMac"),
            ]
        ),
        // The CLI. The only target that talks to the on-device model.
        .executableTarget(
            name: "ttm-eval",
            dependencies: [
                "EvalKit",
                .product(name: "TalkToMyMacCore", package: "TalkToMyMac"),
            ],
            linkerSettings: [.linkedFramework("FoundationModels")]
        ),
        .testTarget(
            name: "EvalKitTests",
            dependencies: ["EvalKit"]
        ),
    ]
)
