// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Paozier",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/dagronf/DSFFullTextSearchIndex.git", from: "1.0.0"),
        .package(url: "https://github.com/dagronf/DFSearchKit.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Paozier",
            dependencies: ["DSFFullTextSearchIndex", "DFSearchKit"],
            path: "Sources",
            resources: [.process("Resources")]
        )
    ]
)
