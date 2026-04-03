// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Blimp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BlimpApp", targets: ["Blimp"]),
        .executable(name: "blimp", targets: ["BlimpCLI"]),
    ],
    targets: [
        .executableTarget(
            name: "Blimp",
            path: "Sources/Blimp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "BlimpCLI",
            path: "Sources/BlimpCLI"
        ),
    ]
)
