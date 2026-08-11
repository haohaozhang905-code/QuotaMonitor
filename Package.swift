// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuotaMonitor", targets: ["QuotaMonitor"])],
    targets: [
        .executableTarget(
            name: "QuotaMonitor",
            path: "Sources/QuotaMonitor",
            exclude: ["QuotaMonitor.entitlements"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "QuotaMonitorTests",
            dependencies: ["QuotaMonitor"],
            path: "Tests/QuotaMonitorTests",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
