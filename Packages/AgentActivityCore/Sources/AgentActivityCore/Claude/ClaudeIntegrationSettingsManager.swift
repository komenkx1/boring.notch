import Foundation

public enum ClaudeIntegrationSettingsError: Error, Equatable, Sendable {
    case invalidSettingsRoot
    case invalidHooksSection
    case invalidEnvironmentSection
    case invalidIntegrationState
}

public struct ClaudeIntegrationLocations: Equatable, Sendable {
    public let settingsFile: URL
    public let integrationStateFile: URL
    public let settingsBackupFile: URL
    public let forwardingExecutable: URL

    public init(
        settingsFile: URL,
        integrationStateFile: URL,
        settingsBackupFile: URL,
        forwardingExecutable: URL
    ) {
        self.settingsFile = settingsFile
        self.integrationStateFile = integrationStateFile
        self.settingsBackupFile = settingsBackupFile
        self.forwardingExecutable = forwardingExecutable
    }

    public static func userDefaults(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let claudeDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        return ClaudeIntegrationLocations(
            settingsFile: claudeDirectory.appendingPathComponent("settings.json"),
            integrationStateFile: claudeDirectory.appendingPathComponent(
                "boring-notch-integration-state.json"
            ),
            settingsBackupFile: claudeDirectory.appendingPathComponent(
                "settings.json.boring-notch-backup"
            ),
            forwardingExecutable: claudeDirectory.appendingPathComponent(
                "boring-notch-agent-bridge"
            )
        )
    }
}

public struct ClaudeIntegrationChangeSummary: Equatable, Sendable {
    public let hookEventsAdded: [String]
    public let preservedHookGroupCount: Int
    public let wrapsExistingStatusLine: Bool
    public let settingsBackupWillBeCreated: Bool
    public let renderedSettingsWithRedactedToken: String
}

public struct ClaudeIntegrationInstallationReport: Equatable, Sendable {
    public let settingsFile: URL
    public let integrationStateFile: URL
    public let settingsBackupFile: URL?
    public let hookEventsAdded: [String]
}

public struct ClaudeIntegrationRemovalReport: Equatable, Sendable {
    public let settingsFile: URL
    public let removedHookHandlerCount: Int
    public let restoredPreviousStatusLine: Bool
    public let keptUserReplacementStatusLine: Bool
}

public struct ClaudeIntegrationSettingsManager {
    public static let observedHookEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "MessageDisplay",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PostToolUseFailure",
        "PermissionDenied",
        "Notification",
        "SubagentStart",
        "SubagentStop",
        "TaskCreated",
        "TaskCompleted",
        "Stop",
        "StopFailure",
        "SessionEnd",
        "Elicitation",
        "ElicitationResult"
    ]

    private let locations: ClaudeIntegrationLocations
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder: JSONEncoder

    public init(
        locations: ClaudeIntegrationLocations = .userDefaults()
    ) {
        self.locations = locations
        jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func preview(
        statusForwardingCommand: String,
        interactiveApprovals: Bool = false
    ) throws -> ClaudeIntegrationChangeSummary {
        let fileManager = FileManager.default
        let currentSettings = try readSettings()
        let existingIntegrationState = try readIntegrationState()
        let previousStatusLine: JSONValue?
        if let existingIntegrationState {
            previousStatusLine = existingIntegrationState.previousStatusLine
        } else {
            previousStatusLine = objectValue(currentSettings)?["statusLine"]
        }
        let updatedSettings = try addingIntegration(
            to: currentSettings,
            bearerToken: "<redacted>",
            statusForwardingCommand: statusForwardingCommand,
            interactiveApprovals: interactiveApprovals
        )
        let preservedHookGroupCount = try hookGroupCount(in: currentSettings)

        return ClaudeIntegrationChangeSummary(
            hookEventsAdded: Self.observedHookEvents.filter {
                !containsOwnedHook(for: $0, in: currentSettings)
            },
            preservedHookGroupCount: preservedHookGroupCount,
            wrapsExistingStatusLine: originalCommand(from: previousStatusLine) != nil,
            settingsBackupWillBeCreated: fileManager.fileExists(atPath: locations.settingsFile.path)
                && !fileManager.fileExists(atPath: locations.settingsBackupFile.path),
            renderedSettingsWithRedactedToken: try encodedString(updatedSettings)
        )
    }

    public func install(
        bearerToken: String,
        statusForwardingCommand: String,
        interactiveApprovals: Bool = false
    ) throws -> ClaudeIntegrationInstallationReport {
        let fileManager = FileManager.default
        let currentSettings = try readSettings()
        let existingIntegrationState = try readIntegrationState()
        let integrationState = existingIntegrationState ?? ClaudeIntegrationState(
            previousStatusLine: objectValue(currentSettings)?["statusLine"],
            statusForwardingCommand: statusForwardingCommand
        )
        let hookEventsAdded = Self.observedHookEvents.filter {
            !containsOwnedHook(for: $0, in: currentSettings)
        }
        let updatedSettings = try addingIntegration(
            to: currentSettings,
            bearerToken: bearerToken,
            statusForwardingCommand: statusForwardingCommand,
            interactiveApprovals: interactiveApprovals
        )

        try fileManager.createDirectory(
            at: locations.settingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let settingsBackupFile: URL?
        if fileManager.fileExists(atPath: locations.settingsFile.path),
           !fileManager.fileExists(atPath: locations.settingsBackupFile.path) {
            try fileManager.copyItem(
                at: locations.settingsFile,
                to: locations.settingsBackupFile
            )
            try applyPrivateFilePermissions(to: locations.settingsBackupFile)
            settingsBackupFile = locations.settingsBackupFile
        } else {
            settingsBackupFile = nil
        }

        try write(integrationState, to: locations.integrationStateFile)
        try write(updatedSettings, to: locations.settingsFile)

        return ClaudeIntegrationInstallationReport(
            settingsFile: locations.settingsFile,
            integrationStateFile: locations.integrationStateFile,
            settingsBackupFile: settingsBackupFile,
            hookEventsAdded: hookEventsAdded
        )
    }

    public func uninstall() throws -> ClaudeIntegrationRemovalReport {
        let fileManager = FileManager.default
        let currentSettings = try readSettings()
        let integrationState = try readIntegrationState()
        var settingsObject = try requiredObject(from: currentSettings)
        let removal = try removingOwnedHooks(from: settingsObject["hooks"])
        settingsObject["hooks"] = removal.remainingHooks

        if case .object(var environmentVariables) = settingsObject["env"] {
            environmentVariables.removeValue(
                forKey: AgentBridgeConfiguration.claudeTokenEnvironmentName
            )
            settingsObject["env"] = environmentVariables.isEmpty
                ? nil
                : .object(environmentVariables)
        }

        let currentStatusLine = settingsObject["statusLine"]
        let currentStatusCommand = originalCommand(from: currentStatusLine)
        let ownsCurrentStatusLine = currentStatusCommand == integrationState?.statusForwardingCommand
        let restoredPreviousStatusLine: Bool
        let keptUserReplacementStatusLine: Bool

        if ownsCurrentStatusLine {
            settingsObject["statusLine"] = integrationState?.previousStatusLine
            restoredPreviousStatusLine = integrationState?.previousStatusLine != nil
            keptUserReplacementStatusLine = false
        } else {
            restoredPreviousStatusLine = false
            keptUserReplacementStatusLine = currentStatusLine != nil
        }

        if case .object(let remainingHooks) = settingsObject["hooks"],
           remainingHooks.isEmpty {
            settingsObject.removeValue(forKey: "hooks")
        }

        try write(JSONValue.object(settingsObject), to: locations.settingsFile)
        if fileManager.fileExists(atPath: locations.integrationStateFile.path) {
            try fileManager.removeItem(at: locations.integrationStateFile)
        }

        return ClaudeIntegrationRemovalReport(
            settingsFile: locations.settingsFile,
            removedHookHandlerCount: removal.removedHandlerCount,
            restoredPreviousStatusLine: restoredPreviousStatusLine,
            keptUserReplacementStatusLine: keptUserReplacementStatusLine
        )
    }

    public func previousStatusLineCommand() throws -> String? {
        originalCommand(from: try readIntegrationState()?.previousStatusLine)
    }

    public func installedBearerToken() throws -> String? {
        let settings = try readSettings()
        let hasInstalledHook = Self.observedHookEvents.contains {
            containsOwnedHook(for: $0, in: settings)
        }
        guard hasInstalledHook,
              let settingsObject = objectValue(settings),
              case .object(let environmentVariables) = settingsObject["env"],
              case .string(let bearerToken) = environmentVariables[
                AgentBridgeConfiguration.claudeTokenEnvironmentName
              ],
              !bearerToken.isEmpty else {
            return nil
        }
        return bearerToken
    }

    public func forwardingExecutableURL() -> URL {
        locations.forwardingExecutable
    }

    private func readSettings() throws -> JSONValue {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: locations.settingsFile.path) else {
            return .object([:])
        }
        let settingsBytes = try Data(contentsOf: locations.settingsFile)
        let settings = try jsonDecoder.decode(JSONValue.self, from: settingsBytes)
        guard case .object = settings else {
            throw ClaudeIntegrationSettingsError.invalidSettingsRoot
        }
        return settings
    }

    private func readIntegrationState() throws -> ClaudeIntegrationState? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: locations.integrationStateFile.path) else {
            return nil
        }
        let stateBytes = try Data(contentsOf: locations.integrationStateFile)
        do {
            return try jsonDecoder.decode(ClaudeIntegrationState.self, from: stateBytes)
        } catch {
            throw ClaudeIntegrationSettingsError.invalidIntegrationState
        }
    }

    private func addingIntegration(
        to settings: JSONValue,
        bearerToken: String,
        statusForwardingCommand: String,
        interactiveApprovals: Bool
    ) throws -> JSONValue {
        var settingsObject = try requiredObject(from: settings)
        var environmentVariables = try optionalObject(
            from: settingsObject["env"],
            error: .invalidEnvironmentSection
        )
        environmentVariables[AgentBridgeConfiguration.claudeTokenEnvironmentName] = .string(
            bearerToken
        )
        settingsObject["env"] = .object(environmentVariables)

        let hooksWithoutPreviousIntegration = try removingOwnedHooks(
            from: settingsObject["hooks"]
        ).remainingHooks
        var hooks = try optionalObject(
            from: hooksWithoutPreviousIntegration,
            error: .invalidHooksSection
        )
        for eventName in Self.observedHookEvents {
            var hookGroups = try optionalArray(
                from: hooks[eventName],
                error: .invalidHooksSection
            )
            hookGroups.append(ownedHookGroup(interactive: interactiveApprovals && eventName == "PermissionRequest"))
            hooks[eventName] = .array(hookGroups)
        }
        settingsObject["hooks"] = .object(hooks)

        var statusLine = try optionalObject(
            from: settingsObject["statusLine"],
            error: .invalidSettingsRoot
        )
        statusLine["type"] = .string("command")
        statusLine["command"] = .string(statusForwardingCommand)
        settingsObject["statusLine"] = .object(statusLine)
        return .object(settingsObject)
    }

    private func ownedHookGroup(interactive: Bool) -> JSONValue {
        .object([
            "hooks": .array([
                .object([
                    "type": .string("command"),
                    "command": .string(locations.forwardingExecutable.path),
                    "args": .array([.string(interactive ? "request-permission" : "forward-hook")]),
                    "timeout": .number(interactive ? 55 : 1)
                ])
            ])
        ])
    }

    private func containsOwnedHook(for eventName: String, in settings: JSONValue) -> Bool {
        guard let settingsObject = objectValue(settings),
              case .object(let hooks) = settingsObject["hooks"] else {
            return false
        }
        return containsOwnedHook(for: eventName, inHooks: hooks)
    }

    private func containsOwnedHook(
        for eventName: String,
        inHooks hooks: [String: JSONValue]
    ) -> Bool {
        guard case .array(let hookGroups) = hooks[eventName] else {
            return false
        }
        return hookGroups.contains { hookGroup in
            handlers(in: hookGroup).contains(where: isOwnedHook)
        }
    }

    private func removingOwnedHooks(
        from hooksValue: JSONValue?
    ) throws -> (remainingHooks: JSONValue?, removedHandlerCount: Int) {
        guard let hooksValue else {
            return (nil, 0)
        }
        guard case .object(var hooks) = hooksValue else {
            throw ClaudeIntegrationSettingsError.invalidHooksSection
        }
        var removedHandlerCount = 0

        for eventName in Self.observedHookEvents {
            guard case .array(let hookGroups) = hooks[eventName] else {
                continue
            }
            var remainingGroups: [JSONValue] = []

            for hookGroup in hookGroups {
                guard case .object(var hookGroupObject) = hookGroup,
                      case .array(let hookHandlers) = hookGroupObject["hooks"] else {
                    remainingGroups.append(hookGroup)
                    continue
                }
                let remainingHandlers = hookHandlers.filter { hookHandler in
                    if isOwnedHook(hookHandler) {
                        removedHandlerCount += 1
                        return false
                    }
                    return true
                }
                if !remainingHandlers.isEmpty {
                    hookGroupObject["hooks"] = .array(remainingHandlers)
                    remainingGroups.append(.object(hookGroupObject))
                }
            }

            if remainingGroups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = .array(remainingGroups)
            }
        }

        return (hooks.isEmpty ? nil : .object(hooks), removedHandlerCount)
    }

    private func isOwnedHook(_ hookHandler: JSONValue) -> Bool {
        guard case .object(let hookObject) = hookHandler else {
            return false
        }
        let isCurrentCommandHook = hookObject["type"] == .string("command")
            && hookObject["command"] == .string(locations.forwardingExecutable.path)
            && (hookObject["args"] == .array([.string("forward-hook")])
                || hookObject["args"] == .array([.string("request-permission")]))
        let isLegacyHTTPHook = hookObject["type"] == .string("http")
            && hookObject["url"] == .string(
                AgentBridgeConfiguration.claudeHookEndpoint.absoluteString
            )
        return isCurrentCommandHook || isLegacyHTTPHook
    }

    private func handlers(in hookGroup: JSONValue) -> [JSONValue] {
        guard case .object(let hookGroupObject) = hookGroup,
              case .array(let hookHandlers) = hookGroupObject["hooks"] else {
            return []
        }
        return hookHandlers
    }

    private func hookGroupCount(in settings: JSONValue) throws -> Int {
        guard let settingsObject = objectValue(settings),
              let hooksValue = settingsObject["hooks"] else {
            return 0
        }
        guard case .object(let hooks) = hooksValue else {
            throw ClaudeIntegrationSettingsError.invalidHooksSection
        }
        return hooks.values.reduce(into: 0) { count, hookGroups in
            if case .array(let groups) = hookGroups {
                count += groups.count
            }
        }
    }

    private func requiredObject(from jsonValue: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let object) = jsonValue else {
            throw ClaudeIntegrationSettingsError.invalidSettingsRoot
        }
        return object
    }

    private func optionalObject(
        from jsonValue: JSONValue?,
        error: ClaudeIntegrationSettingsError
    ) throws -> [String: JSONValue] {
        guard let jsonValue else {
            return [:]
        }
        guard case .object(let object) = jsonValue else {
            throw error
        }
        return object
    }

    private func optionalArray(
        from jsonValue: JSONValue?,
        error: ClaudeIntegrationSettingsError
    ) throws -> [JSONValue] {
        guard let jsonValue else {
            return []
        }
        guard case .array(let array) = jsonValue else {
            throw error
        }
        return array
    }

    private func objectValue(_ jsonValue: JSONValue) -> [String: JSONValue]? {
        guard case .object(let object) = jsonValue else {
            return nil
        }
        return object
    }

    private func originalCommand(from statusLine: JSONValue?) -> String? {
        guard case .object(let statusLineObject) = statusLine,
              case .string(let command) = statusLineObject["command"] else {
            return nil
        }
        return command
    }

    private func encodedString(_ jsonValue: JSONValue) throws -> String {
        let encodedBytes = try jsonEncoder.encode(jsonValue)
        return String(decoding: encodedBytes, as: UTF8.self)
    }

    private func write<T: Encodable>(_ value: T, to destination: URL) throws {
        let encodedBytes = try jsonEncoder.encode(value)
        try encodedBytes.write(to: destination, options: .atomic)
        try applyPrivateFilePermissions(to: destination)
    }

    private func applyPrivateFilePermissions(to fileURL: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

private struct ClaudeIntegrationState: Codable, Equatable, Sendable {
    let previousStatusLine: JSONValue?
    let statusForwardingCommand: String
}
