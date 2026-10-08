import Foundation

public enum ClaudePermissionDecision: String, Codable, Sendable {
    case allow
    case deny

    public func hookOutput() throws -> Data {
        var decision: [String: JSONValue] = ["behavior": .string(rawValue)]
        if self == .deny {
            decision["message"] = .string("The user denied this request in Boring Notch.")
        }
        return try JSONEncoder().encode(JSONValue.object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PermissionRequest"),
                "decision": .object(decision)
            ])
        ]))
    }
}

public struct ClaudePermissionRequest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let agentRunIdentifier: String
    public let toolName: String
    public let toolInputJSON: String
    public let workingDirectory: String
    public let expiresAt: Date
    public var decision: ClaudePermissionDecision?
}

public struct ClaudePermissionPoll: Codable, Equatable, Sendable {
    public let requestIdentifier: UUID
    public let decision: ClaudePermissionDecision?
}

public actor ClaudePermissionStore {
    private struct WaitingRequest {
        var request: ClaudePermissionRequest
        var lastPolledAt: Date
    }

    private let activityStore: AgentActivityStore
    private var waitingRequests: [UUID: WaitingRequest] = [:]

    public init(activityStore: AgentActivityStore) {
        self.activityStore = activityStore
    }

    public func register(hookBody: Data, at now: Date = Date()) async throws -> ClaudePermissionPoll {
        let hook = try JSONDecoder().decode(JSONValue.self, from: hookBody)
        guard hook["hook_event_name"]?.stringValue == "PermissionRequest",
              let toolName = hook["tool_name"]?.stringValue,
              ["Bash", "Read", "Write", "Edit", "Glob", "Grep"].contains(toolName),
              let workingDirectory = hook["cwd"]?.stringValue,
              !workingDirectory.isEmpty, workingDirectory.utf8.count <= 4_096,
              let sessionIdentifier = hook["session_id"]?.stringValue,
              !sessionIdentifier.isEmpty, sessionIdentifier.utf8.count <= 512,
              case .object = hook["tool_input"] else {
            throw ClaudePermissionError.unsupportedRequest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let toolInputBytes = try encoder.encode(hook["tool_input"])
        guard toolInputBytes.count <= 8_192 else { throw ClaudePermissionError.unsupportedRequest }
        let observedEvent = try ClaudeHookEventDecoder().decodeEvent(from: hookBody, receivedAt: now)
        prune(at: now)
        cancel(runIdentifier: observedEvent.agentRunIdentifier)
        guard waitingRequests.count < 16 else { throw ClaudePermissionError.tooManyRequests }
        let requestIdentifier = UUID()
        let request = ClaudePermissionRequest(
            id: requestIdentifier,
            agentRunIdentifier: observedEvent.agentRunIdentifier,
            toolName: toolName,
            toolInputJSON: String(decoding: toolInputBytes, as: UTF8.self),
            workingDirectory: workingDirectory,
            expiresAt: now.addingTimeInterval(45)
        )
        waitingRequests[requestIdentifier] = WaitingRequest(request: request, lastPolledAt: now)
        await activityStore.apply(AgentActivityEvent(
            agentRunIdentifier: observedEvent.agentRunIdentifier,
            providerName: .claude,
            eventKind: .attentionRequested,
            occurredAt: now,
            workingDirectory: observedEvent.workingDirectory,
            repositoryLabel: observedEvent.repositoryLabel,
            summaryText: observedEvent.summaryText,
            attentionRequest: AgentAttentionRequest(
                requestIdentifier: requestIdentifier.uuidString,
                requestKind: .approval,
                promptText: "Claude requests permission to use \(toolName).",
                canRespond: true
            ),
            providerEventName: "PermissionRequest"
        ))
        return ClaudePermissionPoll(requestIdentifier: requestIdentifier, decision: nil)
    }

    public func requests(at now: Date = Date()) -> [ClaudePermissionRequest] {
        prune(at: now)
        return waitingRequests.values.map(\.request).sorted { $0.expiresAt < $1.expiresAt }
    }

    // Only the native UI calls this method. The hook transport exposes no decision endpoint.
    public func decide(_ decision: ClaudePermissionDecision, requestIdentifier: UUID, at now: Date = Date()) async -> Bool {
        guard await isCurrentRequest(requestIdentifier),
              var waitingRequest = waitingRequests[requestIdentifier],
              isLive(waitingRequest, at: now), waitingRequest.request.decision == nil else { return false }
        waitingRequest.request.decision = decision
        waitingRequests[requestIdentifier] = waitingRequest
        return true
    }

    public func poll(requestIdentifier: UUID, at now: Date = Date()) async -> ClaudePermissionPoll? {
        guard await isCurrentRequest(requestIdentifier),
              var waitingRequest = waitingRequests[requestIdentifier], isLive(waitingRequest, at: now) else {
            waitingRequests.removeValue(forKey: requestIdentifier)
            return nil
        }
        if let decision = waitingRequest.request.decision {
            waitingRequests.removeValue(forKey: requestIdentifier)
            await activityStore.apply(AgentActivityEvent(
                agentRunIdentifier: waitingRequest.request.agentRunIdentifier,
                providerName: .claude, eventKind: .attentionResolved, occurredAt: now,
                summaryText: "Permission decision returned to the hook."
            ))
            return ClaudePermissionPoll(requestIdentifier: requestIdentifier, decision: decision)
        }
        waitingRequest.lastPolledAt = now
        waitingRequests[requestIdentifier] = waitingRequest
        return ClaudePermissionPoll(requestIdentifier: requestIdentifier, decision: nil)
    }

    public func observe(_ event: AgentActivityEvent) -> Bool {
        guard event.providerName == .claude, event.eventKind != .usageUpdated else { return true }
        if event.providerEventName == "Notification",
           waitingRequests.values.contains(where: { $0.request.agentRunIdentifier == event.agentRunIdentifier }) {
            return false
        }
        cancel(runIdentifier: event.agentRunIdentifier)
        return true
    }

    public func removeAll() { waitingRequests.removeAll() }

    private func isCurrentRequest(_ identifier: UUID) async -> Bool {
        guard let waitingRequest = waitingRequests[identifier] else { return false }
        let run = await activityStore.agentRun(identifier: waitingRequest.request.agentRunIdentifier)
        return run?.pendingAttentionRequest?.requestIdentifier == identifier.uuidString
            && run?.activityState == .waitingForApproval
    }

    private func isLive(_ waitingRequest: WaitingRequest, at now: Date) -> Bool {
        now < waitingRequest.request.expiresAt && now.timeIntervalSince(waitingRequest.lastPolledAt) < 3
    }

    private func prune(at now: Date) {
        waitingRequests = waitingRequests.filter { isLive($0.value, at: now) }
    }

    private func cancel(runIdentifier: String) {
        waitingRequests = waitingRequests.filter { $0.value.request.agentRunIdentifier != runIdentifier }
    }
}

public enum ClaudePermissionError: Error {
    case unsupportedRequest
    case tooManyRequests
}
