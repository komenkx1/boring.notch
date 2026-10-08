import Foundation

public struct CodexAccountUsage: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let usageWindows: [AgentUsageWindow]

    public init(fetchedAt: Date, usageWindows: [AgentUsageWindow]) {
        self.fetchedAt = fetchedAt
        self.usageWindows = usageWindows
    }
}

public struct CodexRateLimitsDecoder: Sendable {
    public init() {}

    public func decodeResponse(from responseBody: Data, fetchedAt: Date = Date()) throws -> CodexAccountUsage {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: responseBody)
        let buckets: [(String, RateLimitBucket)]
        if let namedBuckets = response.rateLimitsByLimitId {
            buckets = namedBuckets.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let legacyBucket = response.rateLimits {
            buckets = [(legacyBucket.limitId ?? "codex", legacyBucket)]
        } else {
            throw CodexAccountUsageError.invalidResponse
        }

        let windows = buckets.flatMap { bucketIdentifier, bucket in
            [bucket.primary, bucket.secondary].enumerated().compactMap { windowIndex, quotaWindow -> AgentUsageWindow? in
                guard let quotaWindow, let usedPercentage = quotaWindow.usedPercent,
                      usedPercentage.isFinite, usedPercentage >= 0 else { return nil }
                let duration = quotaWindow.windowDurationMins.flatMap { $0 > 0 ? $0 : nil }
                let durationLabel: String
                if let duration, duration % 1_440 == 0 {
                    let dayCount = duration / 1_440
                    durationLabel = "\(dayCount) \(dayCount == 1 ? "day" : "days")"
                } else if let duration, duration % 60 == 0 {
                    let hourCount = duration / 60
                    durationLabel = "\(hourCount) \(hourCount == 1 ? "hour" : "hours")"
                } else if let duration {
                    durationLabel = "\(duration) \(duration == 1 ? "minute" : "minutes")"
                } else {
                    durationLabel = windowIndex == 0 ? "Primary window" : "Secondary window"
                }
                let bucketLabel = bucket.limitName ?? bucket.limitId ?? bucketIdentifier
                let windowDisambiguation = duration != nil && bucket.primary?.windowDurationMins == bucket.secondary?.windowDurationMins
                    ? (windowIndex == 0 ? " (primary)" : " (secondary)") : ""
                return AgentUsageWindow(windowLabel: "\(bucketLabel) · \(durationLabel)\(windowDisambiguation)",
                    usedPercentage: usedPercentage, windowDurationMinutes: duration,
                    resetsAt: quotaWindow.resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil })
            }
        }
        return CodexAccountUsage(fetchedAt: fetchedAt, usageWindows: windows)
    }
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitBucket?
    let rateLimitsByLimitId: [String: RateLimitBucket]?
}

private struct RateLimitBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
}
