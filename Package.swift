// swift-tools-version:6.0
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Pumpkin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pumpkin", targets: ["Pumpkin"]),
    ],
    targets: [
        // Folder watching, download detection, expiry and persistence. No UI.
        .target(name: "PumpkinCore", swiftSettings: settings),
        .target(name: "PumpkinAudioBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("AudioToolbox")]),
        // Menu bar UI and app model.
        .target(name: "PumpkinApp", dependencies: ["PumpkinCore", "PumpkinAudioBridge"], swiftSettings: settings),
        // The app's entry point.
        .executableTarget(name: "Pumpkin", dependencies: ["PumpkinApp"], swiftSettings: settings),
        // Developer tool: renders every panel state to PNG and runs end-to-end checks.
        .executableTarget(name: "PumpkinQA", dependencies: ["PumpkinApp", "PumpkinCore"], swiftSettings: settings),
        .executableTarget(name: "PumpkinMediaQA", dependencies: ["PumpkinApp"], swiftSettings: settings),
        .executableTarget(name: "PumpkinV2QA", dependencies: ["PumpkinApp", "PumpkinCore"], swiftSettings: settings),
        .testTarget(name: "PumpkinCoreTests", dependencies: ["PumpkinCore"], swiftSettings: settings),
        .testTarget(name: "PumpkinAppTests", dependencies: ["PumpkinApp"], swiftSettings: settings),
    ]
)
