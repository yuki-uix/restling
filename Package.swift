// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Breaktime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Breaktime", targets: ["BreaktimeApp"]),
        .library(name: "PomodoroCore", targets: ["PomodoroCore"])
    ],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(name: "BreaktimeApp", dependencies: ["PomodoroCore"],
                          exclude: ["Resources", "RestCatAssets.swift", "WindowCatView.swift"]),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"]),
        .testTarget(name: "BreaktimeAppTests", dependencies: ["BreaktimeApp"])
    ]
)
