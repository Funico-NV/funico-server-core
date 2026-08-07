// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "funico-server-foundation",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "ServerFoundation", targets: ["ServerFoundation"]),
        .library(name: "ServerFoundationCore", targets: ["ServerFoundationCore"]),
        .library(name: "ServerFoundationLogging", targets: ["ServerFoundationLogging"]),
        .library(name: "ServerFoundationVapor", targets: ["ServerFoundationVapor"]),
        .library(name: "ServerFoundationClient", targets: ["ServerFoundationClient"])
    ],
    dependencies: [
        // 1.11.0 is the floor, not a preference: `LogEvent` and the `log(event:)` LogHandler
        // requirement were introduced there. `MemoryLogHandler` does not compile below it.
        .package(url: "https://github.com/apple/swift-log.git", from: Version(1,11,0)),
        .package(url: "https://github.com/vapor/vapor.git", from: Version(4,0,0))
    ],
    targets: [
        .target(name: "ServerFoundationCore"),
        .target(
            name: "ServerFoundationLogging",
            dependencies: [
                "ServerFoundationCore",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ServerFoundationVapor",
            dependencies: [
                "ServerFoundationCore",
                "ServerFoundationLogging",
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        // Not part of the umbrella: the umbrella is what Vapor servers import, and they have
        // no use for a client. Consumers ask for this product by name.
        .target(
            name: "ServerFoundationClient",
            dependencies: [
                "ServerFoundationCore",
                "ServerFoundationLogging",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ServerFoundation",
            dependencies: [
                "ServerFoundationCore",
                "ServerFoundationLogging",
                "ServerFoundationVapor"
            ]
        ),
        .testTarget(
            name: "ServerFoundationCoreTests",
            dependencies: ["ServerFoundationCore"]
        ),
        .testTarget(
            name: "ServerFoundationLoggingTests",
            dependencies: ["ServerFoundationLogging"]
        ),
        .testTarget(
            name: "ServerFoundationClientTests",
            dependencies: ["ServerFoundationClient"]
        ),
        .testTarget(
            name: "ServerFoundationTests",
            dependencies: ["ServerFoundation"]
        )
    ]
)
