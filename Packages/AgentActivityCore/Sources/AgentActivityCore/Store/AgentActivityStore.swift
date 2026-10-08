import Foundation

public enum AgentEventApplicationResult: Equatable, Sendable {
    case applied
    case ignoredDuplicate
    case ignoredStale
}

public actor AgentActivityStore {
    private let maximumAssistantResponseLength: Int
    private let activityFreshnessInterval: TimeInterval
    private var agentRunsByIdentifier: [String: AgentRun] = [:]
    private var appliedEventIdentifiers: Set<UUID> = []

    public init(maximumAssistantResponseLength: Int = 4_000, activityFreshnessInterval: TimeInterval = 300) {
        self.maximumAssistantResponseLength = maximumAssistantResponseLength
        self.activityFreshnessInterval = max(1, activityFreshnessInterval)
    }

    @discardableResult
    public func apply(_ event: AgentActivityEvent) -> AgentEventApplicationResult {
        guard !appliedEventIdentifiers.contains(event.eventIdentifier) else {
            return .ignoredDuplicate
        }

        if let existingRun = agentRunsByIdentifier[event.agentRunIdentifier],
           event.occurredAt < existingRun.lastEventAt {
            return .ignoredStale
        }

        var agentRun = agentRunsByIdentifier[event.agentRunIdentifier]
            ?? AgentRun(firstEvent: event)

        agentRun.modelLabel = event.modelLabel ?? agentRun.modelLabel
        agentRun.workingDirectory = event.workingDirectory ?? agentRun.workingDirectory
        agentRun.repositoryLabel = event.repositoryLabel ?? agentRun.repositoryLabel

        switch event.eventKind {
        case .runStarted:
            agentRun.activityState = .running
            agentRun.summaryText = event.summaryText ?? agentRun.summaryText
        case .activityChanged:
            agentRun.activityState = .running
            agentRun.pendingAttentionRequest = nil
            applySummary(from: event, to: &agentRun)
        case .attentionRequested:
            agentRun.pendingAttentionRequest = event.attentionRequest
            agentRun.summaryText = event.summaryText ?? event.attentionRequest?.promptText
            agentRun.activityState = waitingState(for: event.attentionRequest)
        case .attentionResolved:
            agentRun.pendingAttentionRequest = nil
            agentRun.activityState = .running
            agentRun.summaryText = event.summaryText ?? agentRun.summaryText
        case .assistantMessageCompleted:
            agentRun.activityState = .running
            agentRun.pendingAttentionRequest = nil
            applySummary(from: event, to: &agentRun)
        case .usageUpdated:
            if agentRun.activityState == .starting {
                agentRun.activityState = .running
            }
            agentRun.usageWindows = event.usageWindows
            agentRun.summaryText = event.summaryText ?? agentRun.summaryText
        case .runCompleted:
            agentRun.activityState = .completed
            agentRun.pendingAttentionRequest = nil
            applySummary(from: event, to: &agentRun)
        case .runFailed:
            agentRun.activityState = .failed
            agentRun.pendingAttentionRequest = nil
            agentRun.summaryText = event.summaryText ?? agentRun.summaryText
        case .runInterrupted:
            agentRun.activityState = .interrupted
            agentRun.pendingAttentionRequest = nil
            agentRun.summaryText = event.summaryText ?? agentRun.summaryText
        }

        agentRun.lastEventAt = event.occurredAt
        if event.eventKind != .usageUpdated {
            agentRun.lastActivityAt = event.occurredAt
        }
        agentRunsByIdentifier[event.agentRunIdentifier] = agentRun
        appliedEventIdentifiers.insert(event.eventIdentifier)
        return .applied
    }

    public func agentRun(identifier: String) -> AgentRun? {
        agentRunsByIdentifier[identifier]
    }

    public func agentRuns() -> [AgentRun] {
        agentRunsByIdentifier.values.sorted { leftRun, rightRun in
            let leftPriority = priority(for: leftRun.activityState)
            let rightPriority = priority(for: rightRun.activityState)

            if leftPriority == rightPriority {
                return leftRun.lastEventAt > rightRun.lastEventAt
            }
            return leftPriority < rightPriority
        }
    }

    public func removeAll() {
        agentRunsByIdentifier.removeAll()
        appliedEventIdentifiers.removeAll()
    }

    public func reconcileActivityFreshness(at currentDate: Date = Date()) {
        for (runIdentifier, var agentRun) in agentRunsByIdentifier {
            guard agentRun.activityState.isConfirmedActive,
                  currentDate.timeIntervalSince(agentRun.lastActivityAt) >= activityFreshnessInterval else { continue }
            agentRun.activityState = .unknown
            agentRunsByIdentifier[runIdentifier] = agentRun
        }
    }

    private func applySummary(from event: AgentActivityEvent, to agentRun: inout AgentRun) {
        guard event.providerEventName == "MessageDisplay",
              let assistantMessageIdentifier = event.providerEventIdentifier else {
            if let summaryText = event.summaryText, !summaryText.isEmpty {
                agentRun.summaryText = summaryText
                if event.eventKind == .runCompleted {
                    agentRun.latestAssistantResponse = summaryText
                }
            }
            return
        }

        let messageFragment = event.summaryText ?? ""
        let existingResponse: String

        if agentRun.latestAssistantMessageIdentifier == assistantMessageIdentifier {
            existingResponse = agentRun.latestAssistantResponse ?? ""
        } else {
            existingResponse = ""
        }

        let combinedResponse = String(
            (existingResponse + messageFragment).suffix(maximumAssistantResponseLength)
        )
        agentRun.latestAssistantMessageIdentifier = assistantMessageIdentifier
        agentRun.latestAssistantResponse = combinedResponse

        if !combinedResponse.isEmpty {
            agentRun.summaryText = combinedResponse
        }
    }

    private func waitingState(for attentionRequest: AgentAttentionRequest?) -> AgentActivityState {
        guard let attentionRequest else {
            return .waitingForUser
        }

        switch attentionRequest.requestKind {
        case .approval:
            return .waitingForApproval
        case .question, .notification:
            return .waitingForUser
        }
    }

    private func priority(for activityState: AgentActivityState) -> Int {
        switch activityState {
        case .waitingForApproval, .waitingForUser:
            return 0
        case .failed, .interrupted:
            return 1
        case .starting, .running:
            return 2
        case .completed, .unknown:
            return 3
        }
    }
}
