// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Amora",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Amora", targets: ["Amora"])],
    targets: [
        .executableTarget(name: "Amora", resources: [.copy("Resources/codex-hook.sh")]),
        .testTarget(name: "AmoraTests", dependencies: ["Amora"])
    ]
)
