// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalkToMyMac",
    platforms: [.macOS("26.0")],
    targets: [
        // Core library — pure logic, fully testable, no macOS UI dependencies
        .target(
            name: "TalkToMyMacCore",
            path: "Sources/TalkToMyMacCore"
        ),

        // macOS app executable
        .executableTarget(
            name: "TalkToMyMac",
            dependencies: [
                "TalkToMyMacCore",
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
    ]
)
