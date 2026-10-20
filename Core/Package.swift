// swift-tools-version: 6.0
import PackageDescription

// SparkPlugCore: everything in SparkPlug that is not UI, EventKit or Shortcuts — the data model,
// the JSON store, time formatting, timeline layout and the planning rules. It has no
// dependencies, so `swift test --package-path Core` runs without an Xcode project.
let package = Package(
    name: "SparkPlugCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SparkPlugCore", targets: ["SparkPlugCore"]),
    ],
    targets: [
        .target(name: "SparkPlugCore"),
        .testTarget(name: "SparkPlugCoreTests", dependencies: ["SparkPlugCore"]),
    ]
)
