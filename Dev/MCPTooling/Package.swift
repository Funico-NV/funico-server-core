// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FunicoMCPTooling",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FunicoMCPTooling", targets: ["FunicoMCPTooling"]),
        .executable(name: "funico-mcp-demo", targets: ["MCPDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "FunicoMCPTooling", dependencies: [.product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "MCPDemo", dependencies: [
            "FunicoMCPTooling", .product(name: "MCP", package: "swift-sdk"),
        ]),
        .testTarget(name: "FunicoMCPToolingTests", dependencies: [
            "FunicoMCPTooling", .product(name: "MCP", package: "swift-sdk"),
        ]),
    ]
)
