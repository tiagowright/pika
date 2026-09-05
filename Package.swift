// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pika",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pika",
            resources: [
                .copy("Resources/JetBrainsMono.ttf")
            ]
        )
    ]
)
