// swift-tools-version:5.9
//
// LiquidGlass — Liquid Glass for SwiftUI on macOS 13 Ventura and later.
//
// The package is split into two layers:
//
//   • LiquidGlassCore — pure Swift, no platform frameworks. Implements the
//     optical model (rounded-rect SDF, bevel height field, dual-surface
//     refraction, chromatic dispersion, Fresnel, multi-light specular,
//     compositing) plus a CPU reference renderer. Builds and runs on Linux,
//     which is how the shipped screenshots are generated and verified.
//
//   • LiquidGlass — the Apple layer. SwiftUI modifiers, AppKit/Metal
//     renderer, and a runtime pass-through to the system Liquid Glass APIs
//     when the app is running on macOS 26 or newer.
//
// The Apple layer is only declared on macOS so that `swift build` and
// `swift test` stay green on Linux CI.

import PackageDescription

var products: [Product] = [
    .library(name: "LiquidGlassCore", targets: ["LiquidGlassCore"]),
    .executable(name: "liquidglass-render", targets: ["liquidglass-render"]),
]

var targets: [Target] = [
    .target(
        name: "LiquidGlassCore",
        path: "Sources/LiquidGlassCore"
    ),
    .executableTarget(
        name: "liquidglass-render",
        dependencies: ["LiquidGlassCore"],
        path: "Sources/liquidglass-render"
    ),
    .testTarget(
        name: "LiquidGlassCoreTests",
        dependencies: ["LiquidGlassCore"],
        path: "Tests/LiquidGlassCoreTests"
    ),
]

#if os(macOS)
products.append(.library(name: "LiquidGlass", targets: ["LiquidGlass"]))
targets.append(
    .target(
        name: "LiquidGlass",
        dependencies: ["LiquidGlassCore"],
        path: "Sources/LiquidGlass"
    )
)
products.append(.executable(name: "liquidglass-demo", targets: ["LiquidGlassDemo"]))
targets.append(
    .executableTarget(
        name: "LiquidGlassDemo",
        dependencies: ["LiquidGlass", "LiquidGlassCore"],
        path: "Sources/LiquidGlassDemo"
    )
)
#endif

let package = Package(
    name: "LiquidGlass",
    platforms: [
        // Ventura is the floor: the SwiftUI surface uses only APIs that
        // exist there, and every newer behaviour is behind #available.
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
