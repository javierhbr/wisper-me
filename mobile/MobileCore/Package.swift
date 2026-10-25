// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WisprMobileCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WisprMobileCore", targets: ["WisprMobileCore"])],
    dependencies: [.package(name: "wisprM", path: "../../desktop")],
    targets: [
        .target(name: "WisprMobileCore", dependencies: [.product(name: "WisprCore", package: "wisprM")]),
        .testTarget(name: "WisprMobileCoreTests", dependencies: ["WisprMobileCore"])
    ]
)
