// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DivoomStats",
    platforms: [.macOS(.v12)],
    targets: [
        .systemLibrary(
            name: "CZstd",
            path: "Sources/CZstd",
            pkgConfig: "libzstd",
            providers: [.brew(["zstd"])]
        ),
        .executableTarget(
            name: "DivoomStats",
            dependencies: ["CZstd"],
            path: "Sources/DivoomStats",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
