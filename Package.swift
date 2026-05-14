// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Paozier",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Paozier",
            path: "Sources"
        )
    ]
)
