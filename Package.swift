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
                // App icons and the menu bar glyph, drawn at runtime (PikaGlyph.swift).
                .copy("Resources/Icons"),
                // OFL 1.1 §2 requires the licence travel with every copy of the
                // font, binaries included — so it ships inside the .app too.
                .copy("Resources/JetBrainsMono-OFL.txt")
            ]
        ),
        .testTarget(
            name: "PikaTests",
            dependencies: ["Pika"]
        )
    ]
)
