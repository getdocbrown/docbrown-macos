// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DocBrown",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DocBrown", targets: ["DocBrown"]), .library(name: "DocBrownCore", targets: ["DocBrownCore"]), .executable(name: "docbrown-cli", targets: ["DocBrownCLI"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "DocBrownCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "DocBrown", dependencies: ["DocBrownCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "DocBrownCLI", dependencies: ["DocBrownCore"]),
        .testTarget(name: "DocBrownCoreTests", dependencies: ["DocBrownCore"]),
        .testTarget(name: "DocBrownAppTests", dependencies: ["DocBrown"])
    ]
)
