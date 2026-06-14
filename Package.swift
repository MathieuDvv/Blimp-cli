// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "blimp",
    targets: [
        .executableTarget(
            name: "blimp",
            path: "Sources/blimp"
        ),
    ]
)
