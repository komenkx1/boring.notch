import Foundation

public struct AgentBridgeRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct AgentBridgeResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data
    public let contentType: String?

    public init(
        statusCode: Int,
        body: Data = Data(),
        contentType: String? = nil
    ) {
        self.statusCode = statusCode
        self.body = body
        self.contentType = contentType
    }
}

public struct AgentBridgeRequestProcessor: Sendable {
    public let maximumRequestBodyLength: Int

    private let tokenAuthenticator: any AgentBridgeTokenAuthenticating
    private let activityStore: AgentActivityStore
    private let claudeHookDecoder: ClaudeHookEventDecoder
    private let claudeStatusDecoder: ClaudeStatusSnapshotDecoder

    public init(
        tokenAuthenticator: any AgentBridgeTokenAuthenticating,
        activityStore: AgentActivityStore,
        maximumRequestBodyLength: Int = 65_536,
        claudeHookDecoder: ClaudeHookEventDecoder = ClaudeHookEventDecoder(),
        claudeStatusDecoder: ClaudeStatusSnapshotDecoder = ClaudeStatusSnapshotDecoder()
    ) {
        self.tokenAuthenticator = tokenAuthenticator
        self.activityStore = activityStore
        self.maximumRequestBodyLength = maximumRequestBodyLength
        self.claudeHookDecoder = claudeHookDecoder
        self.claudeStatusDecoder = claudeStatusDecoder
    }

    public func process(
        _ request: AgentBridgeRequest,
        receivedAt: Date = Date()
    ) async -> AgentBridgeResponse {
        guard request.body.count <= maximumRequestBodyLength else {
            return AgentBridgeResponse(statusCode: 413)
        }
        guard bearerToken(from: request.headers).map(tokenAuthenticator.accepts) == true else {
            return AgentBridgeResponse(statusCode: 401)
        }
        if request.method.uppercased() == "GET" {
            return await snapshotResponse(for: request, generatedAt: receivedAt)
        }
        guard request.method.uppercased() == "POST" else {
            return AgentBridgeResponse(statusCode: 405)
        }
        guard contentType(from: request.headers) == "application/json" else {
            return AgentBridgeResponse(statusCode: 415)
        }

        do {
            let normalizedEvent: AgentActivityEvent

            switch request.path {
            case "/v1/hooks/claude":
                normalizedEvent = try claudeHookDecoder.decodeEvent(
                    from: request.body,
                    receivedAt: receivedAt
                )
            case "/v1/status/claude":
                normalizedEvent = try claudeStatusDecoder.decodeEvent(
                    from: request.body,
                    receivedAt: receivedAt
                )
            default:
                return AgentBridgeResponse(statusCode: 404)
            }

            await activityStore.apply(normalizedEvent)
            return AgentBridgeResponse(statusCode: 204)
        } catch {
            return AgentBridgeResponse(statusCode: 400)
        }
    }

    private func snapshotResponse(
        for request: AgentBridgeRequest,
        generatedAt: Date
    ) async -> AgentBridgeResponse {
        guard request.path == "/v1/agent-runs" else {
            return AgentBridgeResponse(statusCode: 404)
        }

        let agentRuns = await activityStore.agentRuns()
        let snapshot = AgentActivitySnapshot(
            generatedAt: generatedAt,
            agentRuns: agentRuns.map(AgentRunSnapshot.init)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return AgentBridgeResponse(
                statusCode: 200,
                body: try encoder.encode(snapshot),
                contentType: "application/json"
            )
        } catch {
            return AgentBridgeResponse(statusCode: 500)
        }
    }

    private func bearerToken(from headers: [String: String]) -> String? {
        guard let authorizationHeader = header(named: "authorization", in: headers) else {
            return nil
        }
        let headerParts = authorizationHeader.split(
            separator: " ",
            maxSplits: 1,
            omittingEmptySubsequences: true
        )
        guard headerParts.count == 2,
              headerParts[0].caseInsensitiveCompare("Bearer") == .orderedSame else {
            return nil
        }
        return String(headerParts[1])
    }

    private func contentType(from headers: [String: String]) -> String? {
        header(named: "content-type", in: headers)?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func header(named expectedName: String, in headers: [String: String]) -> String? {
        headers.first { headerName, _ in
            headerName.caseInsensitiveCompare(expectedName) == .orderedSame
        }?.value
    }
}
