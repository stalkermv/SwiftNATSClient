// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftNATSClient",
    platforms: [
        .macOS(.v13),// .iOS(.v16), .tvOS(.v16), .watchOS(.v9)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "NATS", targets: ["NATS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-metrics", from: "2.5.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // 1. C wrapper
        .systemLibrary(
            name: "COpenSSL",
            pkgConfig: "openssl",
            providers: [
                .brew(["openssl@3"]),
                .apt(["libssl-dev"])
            ]
        ),
        .target(
            name: "CNATS",
            dependencies: ["COpenSSL"],
            path: "Sources/CNATS",
            exclude: [
                "nats.c/examples",
                "nats.c/test",
                "nats.c/CMakeLists.txt",
                "nats.c/README.md",
                "nats.c/src/stan",
                "nats.c/src/CMakeLists.txt",
                "nats.c/src/libnats.pc.in",
                "nats.c/src/version.h.in",
                "nats.c/src/win"
            ],
            sources: ["shim.c", "nats.c/src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("nats.c/include"),
                .headerSearchPath("nats.c/src"),
                .define("NATS_BUILD_STREAMING", to: "OFF"),
                .define("NATS_DISABLE_LIBUV", to: "ON"),
            ],
            
            linkerSettings: [
                .linkedLibrary("ssl"),
                .linkedLibrary("crypto"),
                .linkedLibrary("z")
            ],
        ),
        // 2. Low-level Swift wrapper
        .target(
            name: "NATSCore",
            dependencies: [
                "CNATS",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics")
            ]
        ),
        // 3. High-level async/await API + ServiceLifecycle
        .target(
            name: "NATS",
            dependencies: [
                "NATSCore",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics")
            ]
        ),
        .testTarget(
            name: "NATSTests",
            dependencies: ["NATS"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["NATS"]
        ),
    ]
)
