// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScreenshotPlus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenshotPlus", targets: ["ScreenshotPlus"]),
    ],
    targets: [
        // Model, persistence, importing and local title generation. No UI.
        .target(name: "ScreenshotPlusCore"),
        // The notch app itself (AppKit + SwiftUI).
        .executableTarget(
            name: "ScreenshotPlus",
            dependencies: ["ScreenshotPlusCore"]
        ),
        .testTarget(
            name: "ScreenshotPlusCoreTests",
            dependencies: ["ScreenshotPlusCore"]
        ),
    ]
)
