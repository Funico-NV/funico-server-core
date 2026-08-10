// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "funico-server-foundation",
    platforms: [
        .iOS(.v17), .macOS(.v13), .tvOS(.v17), .visionOS(.v1), .watchOS(.v10)
    ],
    products: [
        .library(name: "ServerFoundation", targets: ["ServerFoundation"]),
        .library(name: "ServerFoundationCore", targets: ["ServerFoundationCore"]),
        .library(name: "ServerFoundationLogging", targets: ["ServerFoundationLogging"]),
        .library(name: "ServerFoundationVapor", targets: ["ServerFoundationVapor"]),
        .library(name: "ServerFoundationClient", targets: ["ServerFoundationClient"])
    ],
    traits: [
        .trait(name: "Vapor", description: "Enables ServerFoundationVapor and Vapor integrations.")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: Version(1, 11, 0)),
        .package(url: "https://github.com/vapor/vapor.git", from: Version(4, 0, 0))
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
                .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"]))
            ]
        ),
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
                .target(name: "ServerFoundationVapor", condition: .when(traits: ["Vapor"]))
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
            name: "ServerFoundationVaporTests",
            dependencies: [
                .target(name: "ServerFoundationVapor", condition: .when(traits: ["Vapor"]))
            ]
        ),
        .testTarget(
            name: "ServerFoundationTests",
            dependencies: [
                .target(name: "ServerFoundation"),
                .target(name: "ServerFoundationVapor", condition: .when(traits: ["Vapor"]))
            ]
        )
    ]
)
