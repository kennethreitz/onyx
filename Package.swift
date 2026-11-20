// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Onyx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Onyx", targets: ["Onyx"]),
        .library(name: "OnyxSync", targets: ["OnyxSync"]),
    ],
    targets: [
        .target(name: "OnyxCore", path: "Sources/OnyxCore"),
        .executableTarget(name: "Onyx", dependencies: ["OnyxCore"], path: "Sources/Onyx"),
        .testTarget(name: "OnyxCoreTests", dependencies: ["OnyxCore"], path: "Tests/OnyxCoreTests"),
        // Obsidian Sync protocol (reverse-engineered; see docs/obsidian-sync-protocol.md).
        .target(name: "OnyxSync", path: "Sources/OnyxSync"),
        .executableTarget(name: "onyx-sync-poc", dependencies: ["OnyxSync"], path: "Sources/OnyxSyncPOC"),
        .testTarget(name: "OnyxSyncTests", dependencies: ["OnyxSync"], path: "Tests/OnyxSyncTests",
                    resources: [.copy("Resources/obsidian-sync-vectors.json"), .copy("Resources/obsidian-merge-vectors.json")]),
    ]
)
