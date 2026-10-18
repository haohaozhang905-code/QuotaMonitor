// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuotaMonitor", targets: ["QuotaMonitor"])],
    targets: [
        .target(
            name: "CZstd",
            path: "Vendor/CZstd",
            exclude: ["README.md", "LICENSE"],
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "QuotaMonitor",
            dependencies: ["CZstd"],
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
