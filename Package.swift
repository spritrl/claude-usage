// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            path: "Sources/ClaudeUsage",
            resources: [.process("Localization")]
        )
    ]
)
