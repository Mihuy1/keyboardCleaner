// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyCleaner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KeyCleaner", targets: ["KeyCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "KeyCleaner",
            dependencies: [],
            path: "Sources/KeyCleaner"
        )
    ]
)
