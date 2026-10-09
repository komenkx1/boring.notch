import AgentActivityCore
import Foundation

@main
enum ClaudeIntegrationCommand {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) async throws {
        let command = arguments.first ?? "help"
        let locations = ClaudeIntegrationLocations.userDefaults()
        let settingsManager = ClaudeIntegrationSettingsManager(locations: locations)
        let statusForwardingCommand = shellQuoted(locations.forwardingExecutable.path)
            + " forward-status"

        switch command {
        case "preview":
            let changeSummary = try settingsManager.preview(
                statusForwardingCommand: statusForwardingCommand,
                interactiveApprovals: arguments.contains("--interactive-approvals"),
                interactiveQuestions: arguments.contains("--interactive-questions")
            )
            print("Hooks to add: \(changeSummary.hookEventsAdded.joined(separator: ", "))")
            print("Existing hook groups preserved: \(changeSummary.preservedHookGroupCount)")
            print("Wraps existing status line: \(changeSummary.wrapsExistingStatusLine)")
            print("Creates one-time backup: \(changeSummary.settingsBackupWillBeCreated)")
            print("\nProposed ~/.claude/settings.json (token redacted):")
            print(changeSummary.renderedSettingsWithRedactedToken)
        case "install":
            try installForwardingExecutable(at: locations.forwardingExecutable)
            let bearerToken = try settingsManager.installedBearerToken()
                ?? AgentBridgeTokenStore().loadOrCreateToken()
            let installationReport = try settingsManager.install(
                bearerToken: bearerToken,
                statusForwardingCommand: statusForwardingCommand,
                interactiveApprovals: arguments.contains("--interactive-approvals"),
                interactiveQuestions: arguments.contains("--interactive-questions")
            )
            print("Claude integration installed.")
            print("Settings: \(installationReport.settingsFile.path)")
            print("State: \(installationReport.integrationStateFile.path)")
            if let backupFile = installationReport.settingsBackupFile {
                print("Backup: \(backupFile.path)")
            }
            print("Hooks added: \(installationReport.hookEventsAdded.count)")
        case "uninstall":
            let removalReport = try settingsManager.uninstall()
            if FileManager.default.fileExists(atPath: locations.forwardingExecutable.path) {
                try FileManager.default.removeItem(at: locations.forwardingExecutable)
            }
            print("Claude integration removed.")
            print("Hook handlers removed: \(removalReport.removedHookHandlerCount)")
            print("Previous status line restored: \(removalReport.restoredPreviousStatusLine)")
            if removalReport.keptUserReplacementStatusLine {
                print("A status line changed after installation was preserved.")
            }
            print("The one-time settings backup was kept.")
        case "forward-status":
            try await forwardStatusSnapshot(using: settingsManager)
        case "forward-hook":
            let hookBody = try readStandardInput(maximumLength: 65_536)
            await sendAgentPayload(hookBody, to: AgentBridgeConfiguration.claudeHookEndpoint)
        case "request-permission":
            guard let hookBody = try? readStandardInput(maximumLength: 65_536),
                  let bearerToken = ProcessInfo.processInfo.environment[AgentBridgeConfiguration.claudeTokenEnvironmentName] else { return }
            await sendAgentPayload(hookBody, to: AgentBridgeConfiguration.claudeHookEndpoint)
            if let decision = await ClaudePermissionClient().requestDecision(hookBody: hookBody, bearerToken: bearerToken),
               let hookOutput = try? decision.hookOutput() {
                FileHandle.standardOutput.write(hookOutput)
            }
        case "request-question":
            guard let hookBody = try? readStandardInput(maximumLength: 65_536),
                  let hook = try? JSONDecoder().decode(JSONValue.self, from: hookBody) else { return }
            guard hook["hook_event_name"] == .string("PreToolUse"), hook["tool_name"] == .string("AskUserQuestion") else {
                await sendAgentPayload(hookBody, to: AgentBridgeConfiguration.claudeHookEndpoint)
                return
            }
            guard let toolInput = hook["tool_input"],
                  let questionnaire = try? ClaudeQuestionnaire(toolInput: toolInput),
                  let bearerToken = ProcessInfo.processInfo.environment[AgentBridgeConfiguration.claudeTokenEnvironmentName],
                  let answers = await ClaudePermissionClient().requestAnswers(hookBody: hookBody, bearerToken: bearerToken),
                  let hookOutput = try? questionnaire.hookOutput(answers: answers) else { return }
            FileHandle.standardOutput.write(hookOutput)
        case "inspect":
            try await printActivitySnapshot(using: settingsManager)
        case "help", "--help", "-h":
            printUsage()
        default:
            printUsage()
            throw ClaudeIntegrationCommandError.unknownCommand(command)
        }
    }

    private static func installForwardingExecutable(at destination: URL) throws {
        let runningExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
        let executableBytes = try Data(contentsOf: runningExecutable)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try executableBytes.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: destination.path
        )
    }

    private static func forwardStatusSnapshot(
        using settingsManager: ClaudeIntegrationSettingsManager
    ) async throws {
        let statusBody = try readStandardInput(maximumLength: 65_536)
        await sendAgentPayload(statusBody, to: AgentBridgeConfiguration.claudeStatusEndpoint)

        guard let previousStatusCommand = try settingsManager.previousStatusLineCommand() else {
            return
        }
        let previousStatusOutput = try runStatusCommand(
            previousStatusCommand,
            input: statusBody
        )
        FileHandle.standardOutput.write(previousStatusOutput)
    }

    private static func printActivitySnapshot(
        using settingsManager: ClaudeIntegrationSettingsManager
    ) async throws {
        guard let bearerToken = try settingsManager.installedBearerToken() else {
            throw ClaudeIntegrationCommandError.integrationNotInstalled
        }

        var snapshotRequest = URLRequest(url: AgentBridgeConfiguration.activitySnapshotEndpoint)
        snapshotRequest.httpMethod = "GET"
        snapshotRequest.timeoutInterval = 2
        snapshotRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (snapshotBody, response) = try await URLSession.shared.data(for: snapshotRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeIntegrationCommandError.unexpectedResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ClaudeIntegrationCommandError.bridgeStatus(httpResponse.statusCode)
        }

        let snapshotObject = try JSONSerialization.jsonObject(with: snapshotBody)
        let readableSnapshot = try JSONSerialization.data(
            withJSONObject: snapshotObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        print(String(decoding: readableSnapshot, as: UTF8.self))
    }

    private static func sendAgentPayload(_ requestBody: Data, to endpoint: URL) async {
        guard let bearerToken = ProcessInfo.processInfo.environment[
            AgentBridgeConfiguration.claudeTokenEnvironmentName
        ], !bearerToken.isEmpty else {
            return
        }

        var bridgeRequest = URLRequest(url: endpoint)
        bridgeRequest.httpMethod = "POST"
        bridgeRequest.httpBody = requestBody
        bridgeRequest.timeoutInterval = 1
        bridgeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        bridgeRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: bridgeRequest)
    }

    private static func runStatusCommand(_ command: String, input: Data) throws -> Data {
        let statusProcess = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        statusProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        statusProcess.arguments = ["-c", command]
        statusProcess.standardInput = inputPipe
        statusProcess.standardOutput = outputPipe
        statusProcess.standardError = FileHandle.nullDevice
        try statusProcess.run()
        inputPipe.fileHandleForWriting.write(input)
        try inputPipe.fileHandleForWriting.close()
        let statusOutput = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
        statusProcess.waitUntilExit()
        return statusOutput
    }

    private static func readStandardInput(maximumLength: Int) throws -> Data {
        var inputBytes = Data()
        while let nextBytes = try FileHandle.standardInput.read(upToCount: min(4_096, maximumLength + 1 - inputBytes.count)), !nextBytes.isEmpty {
            inputBytes.append(nextBytes)
            guard inputBytes.count <= maximumLength else {
                throw ClaudeIntegrationCommandError.standardInputTooLarge
            }
        }
        return inputBytes
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func printUsage() {
        print(
            """
            Usage: boring-notch-claude-integration <command>

              preview         Show the exact Claude settings merge with the token redacted.
              install         Back up settings, merge Boring Notch hooks, and install forwarding.
              inspect         Print the sanitized in-memory agent activity snapshot.
              uninstall       Remove only Boring Notch entries and restore the prior status line.
              forward-hook    Internal hook forwarding command.
              forward-status  Internal status-line forwarding command.

            Add --interactive-approvals to preview or install to enable single-use Claude tool approvals.
            Add --interactive-questions to preview or install to answer AskUserQuestion in the notch.
            """
        )
    }
}

private enum ClaudeIntegrationCommandError: Error, Equatable {
    case unknownCommand(String)
    case standardInputTooLarge
    case integrationNotInstalled
    case unexpectedResponse
    case bridgeStatus(Int)
}
