import Foundation

public struct ClaudeStatusSnapshotDecoder: Sendable {
    public init() {}

    public func decodeEvent(
        from statusBody: Data,
        receivedAt: Date = Date()
    ) throws -> AgentActivityEvent {
        let statusSnapshot = try JSONDecoder().decode(ClaudeStatusSnapshot.self, from: statusBody)
        var usageWindows: [AgentUsageWindow] = []

        if let contextUsedPercentage = statusSnapshot.contextWindow?.usedPercentage {
            usageWindows.append(
                AgentUsageWindow(
                    windowLabel: "Context window",
                    usedPercentage: contextUsedPercentage
                )
            )
        }

        if let fiveHourWindow = statusSnapshot.rateLimits?.fiveHour {
            usageWindows.append(
                AgentUsageWindow(
                    windowLabel: "5 hours",
                    usedPercentage: fiveHourWindow.usedPercentage,
                    windowDurationMinutes: 300,
                    resetsAt: resetDate(from: fiveHourWindow.resetsAt)
                )
            )
        }

        if let sevenDayWindow = statusSnapshot.rateLimits?.sevenDay {
            usageWindows.append(
                AgentUsageWindow(
                    windowLabel: "7 days",
                    usedPercentage: sevenDayWindow.usedPercentage,
                    windowDurationMinutes: 10_080,
                    resetsAt: resetDate(from: sevenDayWindow.resetsAt)
                )
            )
        }

        if let spendLimit = statusSnapshot.rateLimits?.spendLimit {
            usageWindows.append(
                AgentUsageWindow(
                    windowLabel: "Spend limit",
                    usedPercentage: spendLimit.usedPercentage,
                    resetsAt: resetDate(from: spendLimit.resetsAt)
                )
            )
        }

        let workingDirectory = statusSnapshot.workspace.currentDirectory
        let repositoryLabel = URL(fileURLWithPath: workingDirectory).lastPathComponent

        return AgentActivityEvent(
            agentRunIdentifier: statusSnapshot.sessionIdentifier,
            providerName: .claude,
            eventKind: .usageUpdated,
            occurredAt: receivedAt,
            modelLabel: statusSnapshot.model.displayName,
            workingDirectory: workingDirectory,
            repositoryLabel: repositoryLabel.isEmpty ? nil : repositoryLabel,
            summaryText: "Claude usage updated",
            usageWindows: usageWindows,
            providerEventName: "StatusLine"
        )
    }

    private func resetDate(from epochSeconds: Double?) -> Date? {
        guard let epochSeconds else {
            return nil
        }
        return Date(timeIntervalSince1970: epochSeconds)
    }
}

private struct ClaudeStatusSnapshot: Decodable {
    let sessionIdentifier: String
    let model: ClaudeStatusModel
    let workspace: ClaudeStatusWorkspace
    let contextWindow: ClaudeContextWindow?
    let rateLimits: ClaudeRateLimits?

    enum CodingKeys: String, CodingKey {
        case sessionIdentifier = "session_id"
        case model
        case workspace
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}

private struct ClaudeStatusModel: Decodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct ClaudeStatusWorkspace: Decodable {
    let currentDirectory: String

    enum CodingKeys: String, CodingKey {
        case currentDirectory = "current_dir"
    }
}

private struct ClaudeContextWindow: Decodable {
    let usedPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
    }
}

private struct ClaudeRateLimits: Decodable {
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?
    let spendLimit: ClaudeRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case spendLimit = "spend_limit"
    }
}

private struct ClaudeRateLimitWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
