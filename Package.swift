// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wisprM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WisprCore", targets: ["WisprCore"]),
        .executable(name: "wisprM", targets: ["WisprM"])
    ],
    targets: [
        .target(name: "WisprCore"),
        .executableTarget(name: "WisprM", dependencies: ["WisprCore"], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("AVFoundation"), .linkedFramework("Carbon"),
            .linkedFramework("Security"), .linkedFramework("ServiceManagement")
        ]),
        .executableTarget(name: "WisprCheck", dependencies: ["WisprCore"], path: "Tools/WisprCheck"),
        .testTarget(name: "WisprCoreTests", dependencies: ["WisprCore"]),
        .testTarget(name: "WisprMTests", dependencies: ["WisprM"])
    ]
)
