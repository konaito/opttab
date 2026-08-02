// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OptTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OptTabCore"),
        .executableTarget(name: "OptTab", dependencies: ["OptTabCore"]),
        .testTarget(name: "OptTabCoreTests", dependencies: ["OptTabCore"]),
    ]
)
