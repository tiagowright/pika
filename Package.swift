// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pika",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Pika",
            resources: [
                .copy("Resources/JetBrainsMono.ttf"),
                // OFL 1.1 §2 requires the licence travel with every copy of the
                // font, binaries included — so it ships inside the .app too.
                .copy("Resources/JetBrainsMono-OFL.txt")
            ]
        )
    ]
)
