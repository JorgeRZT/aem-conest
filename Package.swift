// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CDNFiltering",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CDNFiltering", path: "Sources/CDNFiltering")
    ]
)
