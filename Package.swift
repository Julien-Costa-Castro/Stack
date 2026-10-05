// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Stack",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Stack",
            targets: ["Stack"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Stack",
            path: "Sources/Stack"
        )
    ]
)
