// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "funico-server-core",
    platforms: [
        .iOS(.v17), .macOS(.v13), .tvOS(.v17), .visionOS(.v1), .watchOS(.v10)
    ],
    products: [
        .library(name: "ServerKit", targets: ["ServerKit"]),
        .library(name: "ServerCore", targets: ["ServerCore"]),
        .library(name: "ServerCoreLogging", targets: ["ServerCoreLogging"]),
        .library(name: "ServerCoreVapor", targets: ["ServerCoreVapor"]),
        .library(name: "ServerCoreClient", targets: ["ServerCoreClient"]),
        .library(name: "ServerCoreTesting", targets: ["ServerCoreTesting"]),

        // Deprecated: the 2.x names, kept for one major version so that moving to
        // funico-server-core is a URL change first and an import change later. Each is a
        // single `@_exported import` of its successor. Removed in 4.0.0.
        .library(name: "ServerFoundation", targets: ["ServerFoundation"]),
        .library(name: "ServerFoundationCore", targets: ["ServerFoundationCore"]),
        .library(name: "ServerFoundationLogging", targets: ["ServerFoundationLogging"]),
        .library(name: "ServerFoundationVapor", targets: ["ServerFoundationVapor"]),
        .library(name: "ServerFoundationClient", targets: ["ServerFoundationClient"])
    ],
    traits: [
        .trait(name: "Vapor", description: "Enables ServerCoreVapor and Vapor integrations.")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: Version(1, 11, 0)),
        .package(url: "https://github.com/vapor/vapor.git", from: Version(4, 0, 0))
    ],
    targets: [
        .target(name: "ServerCore"),
        .target(
            name: "ServerCoreLogging",
            dependencies: [
                "ServerCore",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ServerCoreVapor",
            dependencies: [
                "ServerCore",
                "ServerCoreLogging",
                .product(name: "Vapor", package: "vapor", condition: .when(traits: ["Vapor"]))
            ]
        ),
        .target(
            name: "ServerCoreClient",
            dependencies: [
                "ServerCore",
                "ServerCoreLogging",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ServerCoreTesting",
            dependencies: ["ServerCore"]
        ),
        .target(
            name: "ServerKit",
            dependencies: [
                "ServerCore",
                "ServerCoreLogging",
                .target(name: "ServerCoreVapor", condition: .when(traits: ["Vapor"]))
            ]
        ),
        .testTarget(
            name: "ServerCoreTests",
            dependencies: ["ServerCore"]
        ),
        .testTarget(
            name: "ServerCoreTestingTests",
            dependencies: ["ServerCoreTesting"]
        ),
        .testTarget(
            name: "ServerCoreLoggingTests",
            dependencies: ["ServerCoreLogging"]
        ),
        .testTarget(
            name: "ServerCoreClientTests",
            dependencies: ["ServerCoreClient"]
        ),
        .testTarget(
            name: "ServerCoreVaporTests",
            dependencies: [
                .target(name: "ServerCoreVapor", condition: .when(traits: ["Vapor"]))
            ]
        ),
        .testTarget(
            name: "ServerKitTests",
            dependencies: [
                .target(name: "ServerKit"),
                .target(name: "ServerCoreVapor", condition: .when(traits: ["Vapor"]))
            ]
        ),

        // MARK: Deprecated 2.x module names
        //
        // Separate modules rather than typealiases: an `@_exported import` re-exports extension
        // members (`Application.enableAgentControl`, `URL.webSocketURL`) too, and a typealias
        // cannot. Every public type keeps its name, so code written against 2.x compiles unchanged.

        .target(
            name: "ServerFoundation",
            dependencies: [
                "ServerKit",
                .target(name: "ServerCoreVapor", condition: .when(traits: ["Vapor"]))
            ],
            path: "Sources/Compatibility/ServerFoundation"
        ),
        .target(name: "ServerFoundationCore", dependencies: ["ServerCore"], path: "Sources/Compatibility/ServerFoundationCore"),
        .target(name: "ServerFoundationLogging", dependencies: ["ServerCoreLogging"], path: "Sources/Compatibility/ServerFoundationLogging"),
        .target(name: "ServerFoundationVapor", dependencies: ["ServerCoreVapor"], path: "Sources/Compatibility/ServerFoundationVapor"),
        .target(name: "ServerFoundationClient", dependencies: ["ServerCoreClient"], path: "Sources/Compatibility/ServerFoundationClient"),
        .testTarget(
            name: "CompatibilityTests",
            dependencies: [
                "ServerFoundation",
                "ServerFoundationCore",
                "ServerFoundationLogging",
                "ServerFoundationClient",
                .target(name: "ServerFoundationVapor", condition: .when(traits: ["Vapor"]))
            ]
        )
    ]
)
