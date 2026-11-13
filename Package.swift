// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FinderWheel",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "FinderWheelCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FinderWheel",
            dependencies: ["FinderWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FinderWheelCoreTests",
            dependencies: ["FinderWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
