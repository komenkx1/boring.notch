// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AgentActivityCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "boring-notch-codex-integration", targets: ["CodexIntegrationCommand"]),
        .library(
            name: "AgentActivityCore",
            targets: ["AgentActivityCore"]
        ),
        .executable(
            name: "boring-notch-claude-integration",
            targets: ["ClaudeIntegrationCommand"]
        )
    ],
    targets: [
        .executableTarget(name: "CodexIntegrationCommand", dependencies: ["AgentActivityCore"]),
        .target(
            name: "AgentActivityCore",
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "ClaudeIntegrationCommand",
            dependencies: ["AgentActivityCore"]
        ),
        .testTarget(
            name: "AgentActivityCoreTests",
            dependencies: ["AgentActivityCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
