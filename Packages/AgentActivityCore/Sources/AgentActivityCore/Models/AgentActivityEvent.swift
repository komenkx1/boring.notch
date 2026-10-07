import Foundation

public enum AgentProvider: String, Codable, Sendable {
    case claude
}

public enum AgentActivityEventKind: String, Codable, Sendable {
    case runStarted
    case activityChanged
    case attentionRequested
    case attentionResolved
    case assistantMessageCompleted
    case usageUpdated
    case runCompleted
    case runFailed
    case runInterrupted
}

public enum AgentAttentionRequestKind: String, Codable, Sendable {
    case approval
    case question
    case notification
}

public struct AgentAttentionRequest: Codable, Equatable, Sendable {
    public let requestIdentifier: String
    public let requestKind: AgentAttentionRequestKind
    public let promptText: String
    public let canRespond: Bool

    public init(
        requestIdentifier: String,
        requestKind: AgentAttentionRequestKind,
        promptText: String,
        canRespond: Bool
    ) {
        self.requestIdentifier = requestIdentifier
        self.requestKind = requestKind
        self.promptText = promptText
        self.canRespond = canRespond
    }
}

public struct AgentUsageWindow: Codable, Equatable, Sendable {
    public let windowLabel: String
    public let usedPercentage: Double
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(
        windowLabel: String,
        usedPercentage: Double,
        windowDurationMinutes: Int? = nil,
        resetsAt: Date? = nil
    ) {
        self.windowLabel = windowLabel
        self.usedPercentage = max(0, usedPercentage)
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public struct AgentActivityEvent: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let eventIdentifier: UUID
    public let agentRunIdentifier: String
    public let providerName: AgentProvider
    public let eventKind: AgentActivityEventKind
    public let occurredAt: Date
    public let modelLabel: String?
    public let workingDirectory: String?
    public let repositoryLabel: String?
    public let summaryText: String?
    public let attentionRequest: AgentAttentionRequest?
    public let usageWindows: [AgentUsageWindow]
    public let providerEventName: String?
    public let providerEventIdentifier: String?

    public init(
        schemaVersion: Int = 1,
        eventIdentifier: UUID = UUID(),
        agentRunIdentifier: String,
        providerName: AgentProvider,
        eventKind: AgentActivityEventKind,
        occurredAt: Date = Date(),
        modelLabel: String? = nil,
        workingDirectory: String? = nil,
        repositoryLabel: String? = nil,
        summaryText: String? = nil,
        attentionRequest: AgentAttentionRequest? = nil,
        usageWindows: [AgentUsageWindow] = [],
        providerEventName: String? = nil,
        providerEventIdentifier: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventIdentifier = eventIdentifier
        self.agentRunIdentifier = agentRunIdentifier
        self.providerName = providerName
        self.eventKind = eventKind
        self.occurredAt = occurredAt
        self.modelLabel = modelLabel
        self.workingDirectory = workingDirectory
        self.repositoryLabel = repositoryLabel
        self.summaryText = summaryText
        self.attentionRequest = attentionRequest
        self.usageWindows = usageWindows
        self.providerEventName = providerEventName
        self.providerEventIdentifier = providerEventIdentifier
    }
}
