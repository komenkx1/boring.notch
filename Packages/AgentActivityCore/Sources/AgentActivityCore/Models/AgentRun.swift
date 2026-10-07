import Foundation

public enum AgentActivityState: String, Codable, Sendable {
    case starting
    case running
    case waitingForApproval
    case waitingForUser
    case completed
    case failed
    case interrupted
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
    }
}
