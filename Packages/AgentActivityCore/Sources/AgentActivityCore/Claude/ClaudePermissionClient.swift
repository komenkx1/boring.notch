import Foundation

public struct ClaudePermissionClient: Sendable {
    private let endpoint: URL

    public init(endpoint: URL = AgentBridgeConfiguration.claudePermissionEndpoint) {
        self.endpoint = endpoint
    }

    public func requestDecision(hookBody: Data, bearerToken: String) async -> ClaudePermissionDecision? {
        await requestResponse(hookBody: hookBody, bearerToken: bearerToken, timeoutSeconds: 44)?.decision
    }

    public func requestAnswers(hookBody: Data, bearerToken: String) async -> [String: String]? {
        await requestResponse(hookBody: hookBody, bearerToken: bearerToken, timeoutSeconds: 179)?.answers
    }

    private func requestResponse(hookBody: Data, bearerToken: String, timeoutSeconds: Int) async -> ClaudePermissionPoll? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        guard !bearerToken.isEmpty,
              let registration = await send(method: "POST", to: endpoint, body: hookBody, bearerToken: bearerToken) else { return nil }
        let pollingEndpoint = endpoint.appendingPathComponent(registration.requestIdentifier.uuidString)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            guard let permissionPoll = await send(method: "GET", to: pollingEndpoint, body: nil, bearerToken: bearerToken),
                  permissionPoll.requestIdentifier == registration.requestIdentifier else { return nil }
            if permissionPoll.decision != nil || permissionPoll.answers != nil { return permissionPoll }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return nil }
        }
        return nil
    }

    private func send(method: String, to endpoint: URL, body: Data?, bearerToken: String) async -> ClaudePermissionPoll? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        guard let (responseBody, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, responseBody.count <= 32_768 else { return nil }
        return try? JSONDecoder().decode(ClaudePermissionPoll.self, from: responseBody)
    }
}
