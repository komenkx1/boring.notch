import Foundation

public struct ClaudePermissionClient: Sendable {
    private let endpoint: URL

    public init(endpoint: URL = AgentBridgeConfiguration.claudePermissionEndpoint) {
        self.endpoint = endpoint
    }

    public func requestDecision(hookBody: Data, bearerToken: String) async -> ClaudePermissionDecision? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(44))
        guard !bearerToken.isEmpty,
              let registration = await send(method: "POST", to: endpoint, body: hookBody, bearerToken: bearerToken) else { return nil }
        let pollingEndpoint = endpoint.appendingPathComponent(registration.requestIdentifier.uuidString)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            guard let permissionPoll = await send(method: "GET", to: pollingEndpoint, body: nil, bearerToken: bearerToken),
                  permissionPoll.requestIdentifier == registration.requestIdentifier else { return nil }
            if let decision = permissionPoll.decision { return decision }
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
              (response as? HTTPURLResponse)?.statusCode == 200, responseBody.count <= 1_024 else { return nil }
        return try? JSONDecoder().decode(ClaudePermissionPoll.self, from: responseBody)
    }
}
