import XCTest
@testable import AgentActivityCore

final class MultiProviderRuntimeTests: XCTestCase {
    func testConcurrentProviderHooksExpiryAndReceiverRestart() async throws {
        let store = AgentActivityStore(activityFreshnessInterval: 1)
        let processor = AgentBridgeRequestProcessor(
            tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(expectedBearerToken: "runtime-test"),
            activityStore: store)
        let receiver = LocalAgentHTTPReceiver(requestProcessor: processor)
        let port = try await receiver.start()
        defer { receiver.stop() }

        async let claudeStart: Void = sendHook(port: port, provider: "claude",
            hookJSON: #"{"session_id":"same-session","hook_event_name":"SessionStart","cwd":"/test/repository"}"#)
        async let codexStart: Void = sendHook(port: port, provider: "codex",
            hookJSON: #"{"session_id":"same-session","hook_event_name":"SessionStart","cwd":"/test/repository"}"#)
        async let codexSecondStart: Void = sendHook(port: port, provider: "codex",
            hookJSON: #"{"session_id":"second","hook_event_name":"SessionStart","cwd":"/test/repository"}"#)
        _ = try await (claudeStart, codexStart, codexSecondStart)
        var runs = await store.agentRuns()
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs.filter { $0.activityState.isConfirmedActive }.count, 3)

        try await sendHook(port: port, provider: "codex",
            hookJSON: #"{"session_id":"second","hook_event_name":"Stop","last_assistant_message":"Second run finished"}"#)
        let latestEventDate = try XCTUnwrap(runs.map(\.lastEventAt).max())
        await store.reconcileActivityFreshness(at: latestEventDate.addingTimeInterval(2))
        runs = await store.agentRuns()
        XCTAssertEqual(runs.filter { $0.activityState == .unknown }.count, 2)
        XCTAssertEqual(runs.filter { $0.activityState == .completed }.count, 1)
        XCTAssertEqual(runs.filter { $0.activityState.isConfirmedActive }.count, 0)

        receiver.stop()
        let restartedStore = AgentActivityStore()
        let restartedProcessor = AgentBridgeRequestProcessor(
            tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(expectedBearerToken: "runtime-test"),
            activityStore: restartedStore)
        let restartedReceiver = LocalAgentHTTPReceiver(requestProcessor: restartedProcessor)
        let restartedPort = try await restartedReceiver.start()
        defer { restartedReceiver.stop() }
        let emptyRuns = await restartedStore.agentRuns()
        XCTAssertTrue(emptyRuns.isEmpty)
        try await sendHook(port: restartedPort, provider: "claude",
            hookJSON: #"{"session_id":"after-restart","hook_event_name":"SessionStart","cwd":"/test/repository"}"#)
        let newRuns = await restartedStore.agentRuns()
        XCTAssertEqual(newRuns.count, 1)
        XCTAssertEqual(newRuns.first?.activityState, .running)
    }

    private func sendHook(port: UInt16, provider: String, hookJSON: String) async throws {
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/hooks/\(provider)"))
        var hookRequest = URLRequest(url: endpoint)
        hookRequest.httpMethod = "POST"
        hookRequest.httpBody = Data(hookJSON.utf8)
        hookRequest.timeoutInterval = 3
        hookRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        hookRequest.setValue("Bearer runtime-test", forHTTPHeaderField: "Authorization")
        let (_, hookResponse) = try await URLSession.shared.data(for: hookRequest)
        XCTAssertEqual((hookResponse as? HTTPURLResponse)?.statusCode, 204)
    }
}
