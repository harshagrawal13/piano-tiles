// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PianoTiles",
    platforms: [.iOS(.v17)],
    products: [
        .executable(name: "PianoTiles", targets: ["PianoTiles"])
    ],
    targets: [
        .executableTarget(
            name: "PianoTiles",
            path: "Sources"
        )
    ]
)
