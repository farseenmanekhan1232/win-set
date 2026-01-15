// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinSet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "winset", targets: ["WinSet"])
    ],
    dependencies: [
        // TOML config parsing
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "WinSet",
            dependencies: ["TOMLKit"],
            path: "Sources/WinSet"
        )
    ]
)
