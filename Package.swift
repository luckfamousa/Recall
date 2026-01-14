// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Recall",
            path: "Sources/Recall"
        )
    ]
)
