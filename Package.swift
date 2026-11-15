// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "s-mpc",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "s-mpc", targets: ["SMPC"])],
    targets: [.executableTarget(name: "SMPC", path: "Sources/SMPC")]
)
