// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSpeaki",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSpeaki",
            path: "Sources/ClaudeSpeaki",
            resources: [
                .copy("../Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "ClaudeSpeakiTests",
            dependencies: ["ClaudeSpeaki"],
            path: "Tests/ClaudeSpeakiTests"
        ),
    ]
)
