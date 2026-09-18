// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StudyHamster",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StudyHamster", targets: ["StudyHamster"]),
    ],
    targets: [
        // Pure logic: pomodoro planning/engine, duration parsing, window selection & geometry.
        .target(name: "HamsterCore", path: "Sources/HamsterCore"),
        // SwiftUI drawing: the hamster figure, its animator, the speech bubble and the stage.
        .target(name: "HamsterUI", path: "Sources/HamsterUI"),
        // The menu-bar app: floating panel, window tracking, timers, sounds, settings.
        .executableTarget(name: "StudyHamster", dependencies: ["HamsterCore", "HamsterUI"], path: "Sources/StudyHamster"),
        // Self-checks for HamsterCore (XCTest / swift-testing are unavailable with Command Line Tools only).
        .executableTarget(name: "HamsterChecks", dependencies: ["HamsterCore"], path: "Sources/HamsterChecks"),
        // Renders hamster poses and bubbles to PNG for visual review, and the app icon set.
        .executableTarget(name: "HamsterSnapshots", dependencies: ["HamsterUI"], path: "Sources/HamsterSnapshots"),
    ]
)
