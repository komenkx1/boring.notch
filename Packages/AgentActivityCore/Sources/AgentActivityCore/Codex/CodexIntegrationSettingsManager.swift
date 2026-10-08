import Foundation

public enum CodexIntegrationSettingsError: Error {
    case invalidHooksFile
}

public struct CodexIntegrationSettingsManager {
    public static let observedHookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "SubagentStart", "SubagentStop", "Stop", "Interrupt", "SessionEnd"
    ]

    public let hooksFile: URL
    public let forwardingExecutable: URL
    public let tokenFile: URL
    private let backupFile: URL

    public init(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        hooksFile = codexDirectory.appendingPathComponent("hooks.json")
        forwardingExecutable = codexDirectory.appendingPathComponent("boring-notch-codex-bridge")
        tokenFile = codexDirectory.appendingPathComponent("boring-notch-codex-token")
        backupFile = codexDirectory.appendingPathComponent("hooks.json.boring-notch-backup")
    }

    public func preview() throws -> Data {
        try encode(addingHooks(to: readHooks()))
    }

    public func install(executableBytes: Data) throws {
        let updatedHooks = try preview()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: hooksFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: hooksFile.path), !fileManager.fileExists(atPath: backupFile.path) {
            try fileManager.copyItem(at: hooksFile, to: backupFile)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupFile.path)
        }
        try executableBytes.write(to: forwardingExecutable, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: forwardingExecutable.path)
        try updatedHooks.write(to: hooksFile, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksFile.path)
    }

    public func uninstall() throws {
        if FileManager.default.fileExists(atPath: hooksFile.path) {
            var root = try readHooks()
            var remainingHooks = try removingOwnedHooks(from: root)
            if let backupBytes = try? Data(contentsOf: backupFile),
               let backupRoot = try JSONSerialization.jsonObject(with: backupBytes) as? [String: Any],
               let originalHooks = backupRoot["hooks"] as? [String: Any] {
                for eventName in Self.observedHookEvents where remainingHooks[eventName] == nil {
                    if let originalGroups = originalHooks[eventName] as? [[String: Any]], originalGroups.isEmpty {
                        remainingHooks[eventName] = originalGroups
                    }
                }
            }
            root["hooks"] = remainingHooks
            try encode(root).write(to: hooksFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksFile.path)
        }
        if FileManager.default.fileExists(atPath: forwardingExecutable.path) {
            try FileManager.default.removeItem(at: forwardingExecutable)
        }
        if FileManager.default.fileExists(atPath: tokenFile.path) {
            try FileManager.default.removeItem(at: tokenFile)
        }
    }

    private var forwardingCommand: String {
        "'" + forwardingExecutable.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "' forward-hook"
    }

    private func readHooks() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksFile.path) else { return ["hooks": [String: Any]()] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile)) as? [String: Any] else {
            throw CodexIntegrationSettingsError.invalidHooksFile
        }
        return root
    }

    private func removingOwnedHooks(from root: [String: Any]) throws -> [String: Any] {
        if root["hooks"] == nil { return [:] }
        guard var hooksByEvent = root["hooks"] as? [String: Any] else {
            throw CodexIntegrationSettingsError.invalidHooksFile
        }
        for eventName in Self.observedHookEvents {
            guard let configuredGroups = hooksByEvent[eventName] else { continue }
            guard let groups = configuredGroups as? [[String: Any]] else {
                throw CodexIntegrationSettingsError.invalidHooksFile
            }
            var preservedGroups: [[String: Any]] = []
            for var group in groups {
                if group["hooks"] == nil {
                    preservedGroups.append(group)
                    continue
                }
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    throw CodexIntegrationSettingsError.invalidHooksFile
                }
                let preservedHandlers = handlers.filter { $0["command"] as? String != forwardingCommand }
                if !preservedHandlers.isEmpty || handlers.isEmpty {
                    group["hooks"] = preservedHandlers
                    preservedGroups.append(group)
                }
            }
            if preservedGroups.isEmpty && !groups.isEmpty { hooksByEvent.removeValue(forKey: eventName) }
            else { hooksByEvent[eventName] = preservedGroups }
        }
        return hooksByEvent
    }

    private func addingHooks(to root: [String: Any]) throws -> [String: Any] {
        var updatedRoot = root
        var hooksByEvent = try removingOwnedHooks(from: root)
        for eventName in Self.observedHookEvents {
            var groups = hooksByEvent[eventName] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": forwardingCommand, "timeout": 2]]])
            hooksByEvent[eventName] = groups
        }
        updatedRoot["hooks"] = hooksByEvent
        return updatedRoot
    }

    private func encode(_ hooks: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: hooks, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
