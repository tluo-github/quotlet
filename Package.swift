// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quotlet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Quotlet", path: "Sources/Quotlet", resources: [.process("ProviderAssets")]),
        .testTarget(name: "QuotletTests", dependencies: ["Quotlet"])
    ]
)
