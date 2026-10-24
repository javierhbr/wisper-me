// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WisprMobileInference",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WisprMobileInference", targets: ["WisprMobileInference"])],
    dependencies: [
        .package(path: "../MobileCore"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.2.1")
    ],
    targets: [.target(name: "WisprMobileInference", dependencies: [
        .product(name: "WisprMobileCore", package: "MobileCore"),
        .product(name: "WhisperKit", package: "argmax-oss-swift"),
        .product(name: "FluidAudio", package: "FluidAudio"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Hub", package: "swift-transformers")
    ], swiftSettings: [.swiftLanguageMode(.v5)])]
)
