import XCTest
@testable import AgentActivityCore

final class ClaudeIntegrationSettingsManagerTests: XCTestCase {
    private var testDirectory: URL!
    private var locations: ClaudeIntegrationLocations!

    override func setUpWithError() throws {
        testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "boring-notch-claude-settings-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
        locations = ClaudeIntegrationLocations(
            settingsFile: testDirectory.appendingPathComponent("settings.json"),
            integrationStateFile: testDirectory.appendingPathComponent("integration-state.json"),
            settingsBackupFile: testDirectory.appendingPathComponent("settings.backup.json"),
            forwardingExecutable: testDirectory.appendingPathComponent("forwarder")
        )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try FileManager.default.removeItem(at: testDirectory)
        }
    }

    func testInstallPreservesExistingSettingsAndIsIdempotent() throws {
        let originalSettings = """
        {
          "model": "sonnet",
          "hooks": {
            "PostToolUse": [
              {
                "matcher": "Edit|Write",
                "hooks": [
                  { "type": "command", "command": "existing-review" }
                ]
              }
            ]
          },
          "statusLine": {
            "type": "command",
            "command": "existing-status",
            "padding": 2
          }
        }
        """
        try Data(originalSettings.utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)

        let firstReport = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )
        let secondReport = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )

        XCTAssertEqual(
            firstReport.hookEventsAdded,
            ClaudeIntegrationSettingsManager.observedHookEvents
        )
        XCTAssertTrue(secondReport.hookEventsAdded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.settingsBackupFile.path))

        let installedSettings = try readSettingsObject()
        XCTAssertEqual(installedSettings["model"], .string("sonnet"))
        XCTAssertEqual(
            installedSettings["env"]?[AgentBridgeConfiguration.claudeTokenEnvironmentName],
            .string("test-token")
        )
        XCTAssertEqual(installedSettings["statusLine"]?["command"], .string("forward-status"))
        XCTAssertEqual(installedSettings["statusLine"]?["padding"], .number(2))

        guard case .object(let hooks) = installedSettings["hooks"],
              case .array(let postToolUseGroups) = hooks["PostToolUse"] else {
            return XCTFail("Expected installed hook groups")
        }
        XCTAssertEqual(postToolUseGroups.count, 2)
        XCTAssertEqual(ownedHookCount(in: hooks), 18)
        XCTAssertEqual(try settingsManager.installedBearerToken(), "test-token")
    }

    func testUninstallRemovesOnlyOwnedHooksAndRestoresStatusLine() throws {
        let originalSettings = """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  { "type": "command", "command": "existing-start" }
                ]
              }
            ]
          },
          "statusLine": {
            "type": "command",
            "command": "existing-status"
          }
        }
        """
        try Data(originalSettings.utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)
        _ = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )

        let removalReport = try settingsManager.uninstall()

        XCTAssertEqual(removalReport.removedHookHandlerCount, 18)
        XCTAssertTrue(removalReport.restoredPreviousStatusLine)
        XCTAssertFalse(removalReport.keptUserReplacementStatusLine)
        let restoredSettings = try readSettingsObject()
        XCTAssertNil(
            restoredSettings["env"]?[AgentBridgeConfiguration.claudeTokenEnvironmentName]
        )
        XCTAssertEqual(
            restoredSettings["statusLine"]?["command"],
            .string("existing-status")
        )
        XCTAssertEqual(
            restoredSettings["hooks"]?["SessionStart"]?[0]?["hooks"]?[0]?["command"],
            .string("existing-start")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locations.integrationStateFile.path)
        )
    }

    func testInstallReplacesLegacyHTTPHooksWithCommandForwarders() throws {
        let legacySettings = """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "http",
                    "url": "http://127.0.0.1:48763/v1/hooks/claude"
                  }
                ]
              }
            ]
          }
        }
        """
        try Data(legacySettings.utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)

        _ = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )

        let installedSettings = try readSettingsObject()
        guard case .object(let hooks) = installedSettings["hooks"] else {
            return XCTFail("Expected installed hook groups")
        }
        XCTAssertEqual(ownedHookCount(in: hooks), 18)
        XCTAssertFalse(settingsContainsLegacyHTTPHook(installedSettings))
    }

    func testUninstallKeepsStatusLineChangedAfterInstallation() throws {
        try Data("{}".utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)
        _ = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )
        var installedSettings = try readSettingsObject()
        installedSettings["statusLine"] = .object([
            "type": .string("command"),
            "command": .string("user-replacement")
        ])
        try writeSettingsObject(installedSettings)

        let removalReport = try settingsManager.uninstall()

        XCTAssertFalse(removalReport.restoredPreviousStatusLine)
        XCTAssertTrue(removalReport.keptUserReplacementStatusLine)
        XCTAssertEqual(
            try readSettingsObject()["statusLine"]?["command"],
            .string("user-replacement")
        )
    }

    func testPreviewRedactsTokenAndDoesNotWriteFiles() throws {
        try Data("{}".utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)

        let changeSummary = try settingsManager.preview(
            statusForwardingCommand: "forward-status"
        )

        XCTAssertTrue(changeSummary.renderedSettingsWithRedactedToken.contains("<redacted>"))
        XCTAssertFalse(changeSummary.renderedSettingsWithRedactedToken.contains("test-token"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: locations.integrationStateFile.path)
        )
    }

    func testPreviewAfterInstallUsesOriginalStatusLineState() throws {
        try Data("{}".utf8).write(to: locations.settingsFile)
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)
        _ = try settingsManager.install(
            bearerToken: "test-token",
            statusForwardingCommand: "forward-status"
        )

        let changeSummary = try settingsManager.preview(
            statusForwardingCommand: "forward-status"
        )

        XCTAssertFalse(changeSummary.wrapsExistingStatusLine)
    }

    private func readSettingsObject() throws -> [String: JSONValue] {
        let settingsBytes = try Data(contentsOf: locations.settingsFile)
        let settings = try JSONDecoder().decode(JSONValue.self, from: settingsBytes)
        guard case .object(let settingsObject) = settings else {
            throw ClaudeIntegrationSettingsError.invalidSettingsRoot
        }
        return settingsObject
    }

    private func writeSettingsObject(_ settingsObject: [String: JSONValue]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(JSONValue.object(settingsObject)).write(
            to: locations.settingsFile,
            options: .atomic
        )
    }

    private func ownedHookCount(in hooks: [String: JSONValue]) -> Int {
        hooks.values.reduce(into: 0) { totalCount, hookGroupsValue in
            guard case .array(let hookGroups) = hookGroupsValue else {
                return
            }
            for hookGroup in hookGroups {
                guard case .object(let hookGroupObject) = hookGroup,
                      case .array(let hookHandlers) = hookGroupObject["hooks"] else {
                    continue
                }
                totalCount += hookHandlers.filter { hookHandler in
                    hookHandler["type"] == .string("command")
                        && hookHandler["command"] == .string(locations.forwardingExecutable.path)
                        && hookHandler["args"] == .array([.string("forward-hook")])
                }.count
            }
        }
    }

    private func settingsContainsLegacyHTTPHook(
        _ settingsObject: [String: JSONValue]
    ) -> Bool {
        guard case .object(let hooks) = settingsObject["hooks"] else {
            return false
        }
        return hooks.values.contains { hookGroupsValue in
            guard case .array(let hookGroups) = hookGroupsValue else {
                return false
            }
            return hookGroups.contains { hookGroup in
                guard case .object(let hookGroupObject) = hookGroup,
                      case .array(let hookHandlers) = hookGroupObject["hooks"] else {
                    return false
                }
                return hookHandlers.contains { hookHandler in
                    hookHandler["type"] == .string("http")
                        && hookHandler["url"] == .string(
                            AgentBridgeConfiguration.claudeHookEndpoint.absoluteString
                        )
                }
            }
        }
    }
}

private extension JSONValue {
    subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self,
              array.indices.contains(index) else {
            return nil
        }
        return array[index]
    }
}
