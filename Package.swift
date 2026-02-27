// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ses",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ses", targets: ["ses-cli"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "sesCore",
            path: "Sources/ses",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ses-cli",
            dependencies: ["sesCore"],
            path: "Sources/cli"
        ),
        .executableTarget(
            name: "sesTestRunner",
            dependencies: ["sesCore"],
            path: "Sources/sesTestRunner"
        ),
    ]
)
