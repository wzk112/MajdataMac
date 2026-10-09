// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MajdataMac",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "MajdataMac", targets: ["MajdataMac"]), .library(name: "MajdataCore", targets: ["MajdataCore"])],
    targets: [
        .target(name: "MajdataCore", resources: [.process("Resources")]),
        .executableTarget(name: "MajdataMac", dependencies: ["MajdataCore"], exclude: ["MajdataShaders.metal"], resources: [.copy("Resources")]),
        .testTarget(name: "MajdataCoreTests", dependencies: ["MajdataCore"]),
        .testTarget(name: "MajdataAppTests", dependencies: ["MajdataMac", "MajdataCore"])
    ],
    swiftLanguageModes: [.v6]
)
