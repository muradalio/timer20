// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Timer20",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Timer20", targets: ["Timer20"])
    ],
    targets: [
        .executableTarget(
            name: "Timer20",
            path: "Sources/Timer20"
        )
    ]
)
