// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrainKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BrainKit", targets: ["BrainKit"])],
    targets: [
        .target(name: "BrainKit"),
        .testTarget(name: "BrainKitTests", dependencies: ["BrainKit"]),
    ]
)
