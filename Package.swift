// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyMacLite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CleanMyMacLite", targets: ["CleanMyMacLite"]),
    ],
    targets: [
        .executableTarget(
            name: "CleanMyMacLite",
            path: "Sources/CleanMyMacLite"
        ),
    ]
)
