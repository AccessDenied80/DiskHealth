// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DiskHealth",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DiskHealthCore"),
        .executableTarget(name: "DiskHealth", dependencies: ["DiskHealthCore"]),
        .testTarget(
            name: "DiskHealthCoreTests",
            dependencies: ["DiskHealthCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
