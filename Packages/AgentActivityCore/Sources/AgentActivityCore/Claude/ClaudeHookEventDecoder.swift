import Foundation

public enum ClaudeEventDecodingError: Error, Equatable, Sendable {
    case missingField(String)
    case unsupportedHookEvent(String)
}

public struct ClaudeHookEventDecoder: Sendable {
    private let maximumSummaryLength: Int

    public init(maximumSummaryLength: Int = 2_000) {
        self.maximumSummaryLength = maximumSummaryLength
    }

    public func decodeEvent(
        from hookBody: Data,
        receivedAt: Date = Date()
    ) throws -> AgentActivityEvent {
        let hookInput = try JSONDecoder().decode(ClaudeHookInput.self, from: hookBody)
        let agentRunIdentifier = runIdentifier(for: hookInput)
        let repositoryLabel = repositoryLabel(for: hookInput.workingDirectory)

        switch hookInput.hookEventName {
        case "SessionStart":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runStarted,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: "Claude session started"
            )
        case "UserPromptSubmit":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .activityChanged,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: "Claude is processing a prompt"
            )
        case "MessageDisplay":
            guard let isFinalMessageBatch = hookInput.isFinalMessageBatch else {
                throw ClaudeEventDecodingError.missingField("final")
            }

            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: isFinalMessageBatch ? .assistantMessageCompleted : .activityChanged,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped(hookInput.messageDelta ?? ""),
                providerEventIdentifier: hookInput.messageIdentifier
            )
        case "PreToolUse":
            return activityEvent(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                verb: "Using"
            )
        case "PostToolUse":
            return activityEvent(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                verb: "Finished"
            )
        case "PostToolUseFailure":
            return activityEvent(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                verb: "Tool failed:"
            )
        case "PermissionRequest":
            return permissionRequestEvent(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel
            )
        case "PermissionDenied":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .activityChanged,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped("Permission denied for \(hookInput.toolName ?? "a tool")")
            )
        case "Notification":
            return notificationEvent(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel
            )
        case "Elicitation":
            let promptText = clipped(hookInput.message ?? "Claude needs input")
            let attentionRequest = AgentAttentionRequest(
                requestIdentifier: requestIdentifier(prefix: "elicitation", hookInput: hookInput),
                requestKind: .question,
                promptText: promptText,
                canRespond: false
            )
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .attentionRequested,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: promptText,
                attentionRequest: attentionRequest
            )
        case "ElicitationResult":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .attentionResolved,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: "Claude received the requested input"
            )
        case "SubagentStart":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runStarted,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped("Claude subagent started: \(hookInput.agentType ?? "unknown")")
            )
        case "SubagentStop":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runCompleted,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped(hookInput.lastAssistantMessage ?? "Claude subagent completed")
            )
        case "TaskCreated":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .activityChanged,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped("Started task: \(hookInput.taskSubject ?? "Untitled task")")
            )
        case "TaskCompleted":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .activityChanged,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped("Completed task: \(hookInput.taskSubject ?? "Untitled task")")
            )
        case "Stop":
            if let backgroundTasks = hookInput.backgroundTasks, !backgroundTasks.isEmpty {
                return event(
                    hookInput: hookInput,
                    agentRunIdentifier: agentRunIdentifier,
                    eventKind: .activityChanged,
                    occurredAt: receivedAt,
                    repositoryLabel: repositoryLabel,
                    summaryText: "Claude is waiting for \(backgroundTasks.count) background task(s)"
                )
            }

            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runCompleted,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped(hookInput.lastAssistantMessage ?? "Claude completed the turn")
            )
        case "StopFailure":
            let failureSummary = hookInput.errorDescription ?? "Claude stopped because of an error"
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runFailed,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: clipped(failureSummary)
            )
        case "SessionEnd":
            return event(
                hookInput: hookInput,
                agentRunIdentifier: agentRunIdentifier,
                eventKind: .runCompleted,
                occurredAt: receivedAt,
                repositoryLabel: repositoryLabel,
                summaryText: "Claude session ended"
            )
        default:
            throw ClaudeEventDecodingError.unsupportedHookEvent(hookInput.hookEventName)
        }
    }

    private func activityEvent(
        hookInput: ClaudeHookInput,
        agentRunIdentifier: String,
        occurredAt: Date,
        repositoryLabel: String?,
        verb: String
    ) -> AgentActivityEvent {
        let toolName = hookInput.toolName ?? "tool"
        return event(
            hookInput: hookInput,
            agentRunIdentifier: agentRunIdentifier,
            eventKind: .activityChanged,
            occurredAt: occurredAt,
            repositoryLabel: repositoryLabel,
            summaryText: clipped("\(verb) \(toolName)")
        )
    }

    private func permissionRequestEvent(
        hookInput: ClaudeHookInput,
        agentRunIdentifier: String,
        occurredAt: Date,
        repositoryLabel: String?
    ) -> AgentActivityEvent {
        let toolName = hookInput.toolName ?? "a tool"
        let providerDescription = hookInput.toolInput?["description"]?.stringValue
        let promptText = clipped(providerDescription ?? "Claude requests permission to use \(toolName)")
        let attentionRequest = AgentAttentionRequest(
            requestIdentifier: requestIdentifier(prefix: "permission", hookInput: hookInput),
            requestKind: .approval,
            promptText: promptText,
            canRespond: false
        )

        return event(
            hookInput: hookInput,
            agentRunIdentifier: agentRunIdentifier,
            eventKind: .attentionRequested,
            occurredAt: occurredAt,
            repositoryLabel: repositoryLabel,
            summaryText: promptText,
            attentionRequest: attentionRequest
        )
    }

    private func notificationEvent(
        hookInput: ClaudeHookInput,
        agentRunIdentifier: String,
        occurredAt: Date,
        repositoryLabel: String?
    ) -> AgentActivityEvent {
        let requestKind: AgentAttentionRequestKind = hookInput.notificationType == "permission_prompt"
            ? .approval
            : .notification
        let notificationText = clipped(
            hookInput.message
                ?? hookInput.title
                ?? "Claude sent a notification"
        )
        let attentionRequest = AgentAttentionRequest(
            requestIdentifier: requestIdentifier(prefix: "notification", hookInput: hookInput),
            requestKind: requestKind,
            promptText: notificationText,
            canRespond: false
        )

        return event(
            hookInput: hookInput,
            agentRunIdentifier: agentRunIdentifier,
            eventKind: .attentionRequested,
            occurredAt: occurredAt,
            repositoryLabel: repositoryLabel,
            summaryText: notificationText,
            attentionRequest: attentionRequest
        )
    }

    private func event(
        hookInput: ClaudeHookInput,
        agentRunIdentifier: String,
        eventKind: AgentActivityEventKind,
        occurredAt: Date,
        repositoryLabel: String?,
        summaryText: String?,
        attentionRequest: AgentAttentionRequest? = nil,
        providerEventIdentifier: String? = nil
    ) -> AgentActivityEvent {
        AgentActivityEvent(
            agentRunIdentifier: agentRunIdentifier,
            providerName: .claude,
            eventKind: eventKind,
            occurredAt: occurredAt,
            workingDirectory: hookInput.workingDirectory,
            repositoryLabel: repositoryLabel,
            summaryText: summaryText,
            attentionRequest: attentionRequest,
            providerEventName: hookInput.hookEventName,
            providerEventIdentifier: providerEventIdentifier
        )
    }

    private func runIdentifier(for hookInput: ClaudeHookInput) -> String {
        guard ["SubagentStart", "SubagentStop"].contains(hookInput.hookEventName),
              let agentIdentifier = hookInput.agentIdentifier else {
            return hookInput.sessionIdentifier
        }
        return "\(hookInput.sessionIdentifier):subagent:\(agentIdentifier)"
    }

    private func requestIdentifier(prefix: String, hookInput: ClaudeHookInput) -> String {
        let providerIdentifier = hookInput.turnIdentifier
            ?? hookInput.messageIdentifier
            ?? UUID().uuidString
        return "\(prefix):\(hookInput.sessionIdentifier):\(providerIdentifier)"
    }

    private func repositoryLabel(for workingDirectory: String) -> String? {
        let directoryName = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return directoryName.isEmpty ? nil : directoryName
    }

    private func clipped(_ text: String) -> String {
        String(text.prefix(maximumSummaryLength))
    }
}

private struct ClaudeHookInput: Decodable {
    let sessionIdentifier: String
    let workingDirectory: String
    let hookEventName: String
    let turnIdentifier: String?
    let messageIdentifier: String?
    let messageDelta: String?
    let isFinalMessageBatch: Bool?
    let toolName: String?
    let toolInput: JSONValue?
    let message: String?
    let title: String?
    let notificationType: String?
    let agentIdentifier: String?
    let agentType: String?
    let lastAssistantMessage: String?
    let taskSubject: String?
    let errorDescription: String?
    let backgroundTasks: [ClaudeBackgroundTask]?

    enum CodingKeys: String, CodingKey {
        case sessionIdentifier = "session_id"
        case workingDirectory = "cwd"
        case hookEventName = "hook_event_name"
        case turnIdentifier = "turn_id"
        case messageIdentifier = "message_id"
        case messageDelta = "delta"
        case isFinalMessageBatch = "final"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case title
        case notificationType = "notification_type"
        case agentIdentifier = "agent_id"
        case agentType = "agent_type"
        case lastAssistantMessage = "last_assistant_message"
        case taskSubject = "task_subject"
        case errorDescription = "error"
        case backgroundTasks = "background_tasks"
    }
}

private struct ClaudeBackgroundTask: Decodable {
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case identifier = "id"
    }
}
