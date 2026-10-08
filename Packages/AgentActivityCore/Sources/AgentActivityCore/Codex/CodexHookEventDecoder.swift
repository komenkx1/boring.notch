import Foundation

public enum CodexEventDecodingError: Error, Equatable {
    case missingSessionIdentifier
    case unsupportedHookEvent(String)
}

public struct CodexHookEventDecoder: Sendable {
    public init() {}

    public func decodeEvent(from hookBody: Data, receivedAt: Date = Date()) throws -> AgentActivityEvent {
        let hook = try JSONDecoder().decode(CodexHookInput.self, from: hookBody)
        guard !hook.sessionIdentifier.isEmpty else {
            throw CodexEventDecodingError.missingSessionIdentifier
        }
        let runIdentifier = "codex:\(hook.sessionIdentifier)"
            + (hook.agentIdentifier.map { ":agent:\($0)" } ?? "")
        let eventKind: AgentActivityEventKind
        let summary: String?
        var attentionRequest: AgentAttentionRequest?

        switch hook.hookEventName {
        case "SessionStart", "SubagentStart":
            eventKind = .runStarted
            summary = "Codex session started"
        case "UserPromptSubmit":
            eventKind = .activityChanged
            summary = "Codex is processing a prompt"
        case "PreToolUse", "PostToolUse":
            eventKind = .activityChanged
            let verb = hook.hookEventName == "PreToolUse" ? "Using" : "Finished"
            summary = "\(verb) \(hook.toolName ?? "a tool")"
        case "PermissionRequest":
            eventKind = .attentionRequested
            let permissionSummary = "Codex needs permission for \(hook.toolName ?? "a tool")"
            summary = permissionSummary
            attentionRequest = AgentAttentionRequest(
                requestIdentifier: "\(runIdentifier):\(hook.toolUseIdentifier ?? hook.turnIdentifier ?? "permission")",
                requestKind: .approval,
                promptText: permissionSummary,
                canRespond: false
            )
        case "Stop", "SubagentStop":
            eventKind = .runCompleted
            summary = hook.lastAssistantMessage ?? "Codex completed the turn"
        case "SessionEnd":
            eventKind = .runCompleted
            summary = nil
        case "Interrupt":
            eventKind = .runInterrupted
            summary = "Codex turn interrupted"
        default:
            throw CodexEventDecodingError.unsupportedHookEvent(hook.hookEventName)
        }

        return AgentActivityEvent(
            agentRunIdentifier: runIdentifier,
            providerName: .codex,
            eventKind: eventKind,
            occurredAt: receivedAt,
            modelLabel: hook.model,
            workingDirectory: hook.workingDirectory,
            repositoryLabel: hook.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            summaryText: summary.map { String($0.prefix(2_000)) },
            attentionRequest: attentionRequest,
            providerEventName: hook.hookEventName
        )
    }
}

private struct CodexHookInput: Decodable {
    let sessionIdentifier: String
    let hookEventName: String
    let workingDirectory: String?
    let model: String?
    let turnIdentifier: String?
    let agentIdentifier: String?
    let toolName: String?
    let toolUseIdentifier: String?
    let lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case sessionIdentifier = "session_id"
        case hookEventName = "hook_event_name"
        case workingDirectory = "cwd"
        case model
        case turnIdentifier = "turn_id"
        case agentIdentifier = "agent_id"
        case toolName = "tool_name"
        case toolUseIdentifier = "tool_use_id"
        case lastAssistantMessage = "last_assistant_message"
    }
}
