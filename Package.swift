// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FigmaMetal",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "FigmaMetal", targets: ["FigmaMetal"]),
        .library(name: "FigmaMetalCore", targets: ["FigmaMetalCore"]),
        .executable(name: "figma-metal", targets: ["FigmaMetalDemo"])
    ],
    targets: [
        .target(name: "FigmaMetalCore"),
        .target(name: "FigmaMetal", dependencies: ["FigmaMetalCore"], resources: [.copy("Shaders")]),
        .executableTarget(name: "FigmaMetalDemo", dependencies: ["FigmaMetal"], resources: [.copy("Resources")]),
        .testTarget(name: "FigmaMetalCoreTests", dependencies: ["FigmaMetalCore"]),
        .testTarget(name: "FigmaMetalTests", dependencies: ["FigmaMetal"])
    ]
)
