// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mettle",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "Mettle", targets: ["Mettle"]),
        .library(name: "MettleCore", targets: ["MettleCore"]),
        .executable(name: "mettle", targets: ["MettleDemo"])
    ],
    targets: [
        .target(name: "MettleCore"),
        .target(name: "Mettle", dependencies: ["MettleCore"], resources: [.copy("Shaders")]),
        .target(name: "MettlePreview", dependencies: ["Mettle"], resources: [.copy("References")]),
        .executableTarget(name: "MettleDemo", dependencies: ["Mettle", "MettlePreview"], resources: [.copy("Resources")]),
        .testTarget(name: "MettleCoreTests", dependencies: ["MettleCore"]),
        .testTarget(name: "MettleTests", dependencies: ["Mettle"]),
        .testTarget(name: "MettlePreviewTests", dependencies: ["MettlePreview", "Mettle"])
    ]
)
