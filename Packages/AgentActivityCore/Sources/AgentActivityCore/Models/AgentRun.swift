import Foundation

public enum AgentActivityState: String, Codable, Sendable {
    case starting
    case running
    case waitingForApproval
    case waitingForUser
    case completed
    case failed
    case interrupted
    case unknown

    public var isConfirmedActive: Bool {
        switch self {
        case .starting, .running, .waitingForApproval, .waitingForUser: true
        case .completed, .failed, .interrupted, .unknown: false
        }
    }
}

public struct AgentRun: Codable, Equatable, Sendable, Identifiable {
    public var id: String { agentRunIdentifier }

    public let agentRunIdentifier: String
    public let providerName: AgentProvider
    public var activityState: AgentActivityState
    public var modelLabel: String?
    public var workingDirectory: String?
    public var repositoryLabel: String?
    public var summaryText: String?
    public var latestAssistantResponse: String?
    public var latestAssistantMessageIdentifier: String?
    public var pendingAttentionRequest: AgentAttentionRequest?
    public var usageWindows: [AgentUsageWindow]
    public let startedAt: Date
    public var lastEventAt: Date
    public var lastActivityAt: Date

    public var needsAttention: Bool {
        activityState.isConfirmedActive && pendingAttentionRequest != nil
    }

    init(firstEvent: AgentActivityEvent) {
        agentRunIdentifier = firstEvent.agentRunIdentifier
        providerName = firstEvent.providerName
        activityState = .starting
        modelLabel = firstEvent.modelLabel
        workingDirectory = firstEvent.workingDirectory
        repositoryLabel = firstEvent.repositoryLabel
        summaryText = firstEvent.summaryText
        latestAssistantResponse = nil
        latestAssistantMessageIdentifier = nil
        pendingAttentionRequest = firstEvent.attentionRequest
        usageWindows = firstEvent.usageWindows
        startedAt = firstEvent.occurredAt
        lastEventAt = firstEvent.occurredAt
        lastActivityAt = firstEvent.occurredAt
    }
}
