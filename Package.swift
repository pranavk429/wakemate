// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WakeMate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WakeMate", targets: ["WakeMate"]),
        .executable(name: "WakeMateTests", targets: ["WakeMateTests"]),
    ],
    targets: [
        // All core logic: IOKit, pmset, power monitoring, sleep control, session state
        .target(
            name: "WakeMateCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Menu bar app: MenuBarExtra, popover, settings
        .executableTarget(
            name: "WakeMate",
            dependencies: ["WakeMateCore"]
        ),
        // Test suite executable (runs on both Xcode and Command Line Tools)
        .executableTarget(
            name: "WakeMateTests",
            dependencies: ["WakeMateCore"],
            path: "Tests/WakeMateCoreTests"
        ),
    ]
)
