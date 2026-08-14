// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OptTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OptTabCore"),
        .executableTarget(
            name: "OptTab",
            dependencies: ["OptTabCore"],
            // .app バンドルを持たない単体バイナリなので、Info.plist を __TEXT,__info_plist
            // セクションに埋め込む。CFBundleIdentifier（TCC/権限ダイアログの表示名）と
            // NSHighResolutionCapable（HUDのRetina描画）がこれで効く。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "OptTabCoreTests", dependencies: ["OptTabCore"]),
    ]
)
