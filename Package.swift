// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Onyx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Onyx", targets: ["Onyx"]),
    ],
    targets: [
        .target(name: "OnyxCore", path: "Sources/OnyxCore"),
        .executableTarget(name: "Onyx", dependencies: ["OnyxCore"], path: "Sources/Onyx"),
        .testTarget(name: "OnyxCoreTests", dependencies: ["OnyxCore"], path: "Tests/OnyxCoreTests"),
    ]
)
