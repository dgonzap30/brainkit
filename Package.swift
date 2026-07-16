// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrainKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BrainKit", targets: ["BrainKit"]),
        .library(name: "LodestarPluginKit", targets: ["LodestarPluginKit"]),
        .library(name: "LodestarUI", targets: ["LodestarUI"]),
    ],
    targets: [
        .target(name: "BrainKit"),
        .testTarget(name: "BrainKitTests", dependencies: ["BrainKit"]),
        .target(name: "LodestarPluginKit", dependencies: ["BrainKit"]),
        .testTarget(name: "LodestarPluginKitTests", dependencies: ["LodestarPluginKit"]),
        .target(name: "LodestarUI"),
        .testTarget(name: "LodestarUITests", dependencies: ["LodestarUI"]),
    ]
)
