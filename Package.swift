// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDisplay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sender", targets: ["Sender"]),
        .executable(name: "Receiver", targets: ["Receiver"]),
    ],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),
        .executableTarget(
            name: "Sender",
            dependencies: ["Shared"],
            path: "Sources/Sender",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "Receiver",
            dependencies: ["Shared"],
            path: "Sources/Receiver",
            linkerSettings: [
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ]
)
