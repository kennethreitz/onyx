// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Onyx",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "Onyx", targets: ["Onyx"]),
        .library(name: "OnyxCore", targets: ["OnyxCore"]),
        .library(name: "OnyxSync", targets: ["OnyxSync"]),
    ],
    targets: [
        .target(name: "OnyxCore", path: "Sources/OnyxCore"),
        .executableTarget(name: "Onyx", dependencies: ["OnyxCore", "OnyxSync"], path: "Sources/Onyx"),
        .testTarget(name: "OnyxCoreTests", dependencies: ["OnyxCore"], path: "Tests/OnyxCoreTests"),
        // Obsidian Sync protocol (reverse-engineered; see docs/obsidian-sync-protocol.md).
        .target(name: "OnyxSync", dependencies: ["OnyxCore"], path: "Sources/OnyxSync"),
        // Performance harness against a real vault (see docs/performance.md).
        .executableTarget(name: "onyx-bench", dependencies: ["OnyxCore"], path: "Sources/OnyxBench"),
        .executableTarget(name: "onyx-sync-poc", dependencies: ["OnyxSync"], path: "Sources/OnyxSyncPOC"),
        .testTarget(name: "OnyxSyncTests", dependencies: ["OnyxSync", "OnyxCore"], path: "Tests/OnyxSyncTests",
                    resources: [.copy("Resources/obsidian-sync-vectors.json"), .copy("Resources/obsidian-merge-vectors.json")]),
    ]
)
