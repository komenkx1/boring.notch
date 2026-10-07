import Foundation

public struct AgentActivitySnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let agentRuns: [AgentRunSnapshot]

    public init(generatedAt: Date, agentRuns: [AgentRunSnapshot]) {
        self.generatedAt = generatedAt
        self.agentRuns = agentRuns
    }
}

public struct AgentRunSnapshot: Codable, Equatable, Sendable {
    public let agentRunIdentifier: String
    public let providerName: AgentProvider
    public let activityState: AgentActivityState
    public let modelLabel: String?
    public let repositoryLabel: String?
    public let needsAttention: Bool
    public let usageWindows: [AgentUsageWindow]
    public let startedAt: Date
    public let lastEventAt: Date

    public init(agentRun: AgentRun) {
        agentRunIdentifier = agentRun.agentRunIdentifier
        providerName = agentRun.providerName
        activityState = agentRun.activityState
        modelLabel = agentRun.modelLabel
        repositoryLabel = agentRun.repositoryLabel
        needsAttention = agentRun.pendingAttentionRequest != nil
        usageWindows = agentRun.usageWindows
        startedAt = agentRun.startedAt
        lastEventAt = agentRun.lastEventAt
    }
}
