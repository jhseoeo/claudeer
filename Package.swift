// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudeer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Claudeer",
            path: "Sources/Claudeer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "ClaudeerTests",
            dependencies: ["Claudeer"],
            path: "Tests/ClaudeerTests"
        ),
    ]
)
