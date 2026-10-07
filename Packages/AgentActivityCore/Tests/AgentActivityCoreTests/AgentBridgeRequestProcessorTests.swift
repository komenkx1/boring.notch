import XCTest
@testable import AgentActivityCore

final class AgentBridgeRequestProcessorTests: XCTestCase {
    private let bearerToken = "fixture-token"

    func testAuthenticatedClaudeHookUpdatesStore() async throws {
        let activityStore = AgentActivityStore()
        let requestProcessor = makeRequestProcessor(activityStore: activityStore)
        let hookBody = try FixtureLoader.body(named: "session-start")
        let bridgeRequest = authenticatedRequest(
            path: "/v1/hooks/claude",
            body: hookBody
        )

        let bridgeResponse = await requestProcessor.process(bridgeRequest)

        XCTAssertEqual(bridgeResponse.statusCode, 204)
        let agentRun = await activityStore.agentRun(identifier: "claude-session-123")
        XCTAssertEqual(agentRun?.activityState, .running)
    }

    func testAuthenticatedStatusSnapshotUpdatesUsage() async throws {
        let activityStore = AgentActivityStore()
        let requestProcessor = makeRequestProcessor(activityStore: activityStore)
        let statusBody = try FixtureLoader.body(named: "status-line")

        let bridgeResponse = await requestProcessor.process(
            authenticatedRequest(path: "/v1/status/claude", body: statusBody)
        )

        XCTAssertEqual(bridgeResponse.statusCode, 204)
        let agentRun = await activityStore.agentRun(identifier: "claude-session-123")
        XCTAssertEqual(agentRun?.modelLabel, "Claude Sonnet 4.5")
        XCTAssertEqual(agentRun?.activityState, .running)
        XCTAssertEqual(agentRun?.usageWindows.count, 4)
    }

    func testRejectsMissingOrIncorrectBearerToken() async throws {
        let activityStore = AgentActivityStore()
        let requestProcessor = makeRequestProcessor(activityStore: activityStore)
        let hookBody = try FixtureLoader.body(named: "session-start")
        let missingTokenRequest = AgentBridgeRequest(
            method: "POST",
            path: "/v1/hooks/claude",
            headers: ["Content-Type": "application/json"],
            body: hookBody
        )
        let incorrectTokenRequest = AgentBridgeRequest(
            method: "POST",
            path: "/v1/hooks/claude",
            headers: [
                "Authorization": "Bearer incorrect-token",
                "Content-Type": "application/json"
            ],
            body: hookBody
        )

        let missingTokenResponse = await requestProcessor.process(missingTokenRequest)
        let incorrectTokenResponse = await requestProcessor.process(incorrectTokenRequest)

        XCTAssertEqual(missingTokenResponse.statusCode, 401)
        XCTAssertEqual(incorrectTokenResponse.statusCode, 401)
        let storedAgentRuns = await activityStore.agentRuns()
        XCTAssertTrue(storedAgentRuns.isEmpty)
    }

    func testRejectsOversizedAndMalformedBodies() async {
        let activityStore = AgentActivityStore()
        let requestProcessor = makeRequestProcessor(
            activityStore: activityStore,
            maximumRequestBodyLength: 20
        )
        let oversizedRequest = authenticatedRequest(
            path: "/v1/hooks/claude",
            body: Data(repeating: 1, count: 21)
        )
        let malformedRequest = authenticatedRequest(
            path: "/v1/hooks/claude",
            body: Data("not-json".utf8)
        )

        let oversizedResponse = await requestProcessor.process(oversizedRequest)
        let malformedResponse = await requestProcessor.process(malformedRequest)

        XCTAssertEqual(oversizedResponse.statusCode, 413)
        XCTAssertEqual(malformedResponse.statusCode, 400)
    }

    func testHTTPParserWaitsForCompleteBodyAndRejectsLargeHeaders() {
        let requestHead = "POST /v1/hooks/claude HTTP/1.1\r\n"
            + "Authorization: Bearer fixture-token\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: 2\r\n\r\n"

        let incompleteParse = AgentBridgeHTTPParser.parse(
            Data((requestHead + "{").utf8),
            maximumHeaderLength: 1_024,
            maximumBodyLength: 1_024
        )
        let completeParse = AgentBridgeHTTPParser.parse(
            Data((requestHead + "{}").utf8),
            maximumHeaderLength: 1_024,
            maximumBodyLength: 1_024
        )
        let oversizedHeaderParse = AgentBridgeHTTPParser.parse(
            Data(String(repeating: "x", count: 20).utf8),
            maximumHeaderLength: 10,
            maximumBodyLength: 1_024
        )

        XCTAssertEqual(incompleteParse, .incomplete)
        guard case .request(let parsedRequest) = completeParse else {
            return XCTFail("Expected a complete bridge request")
        }
        XCTAssertEqual(parsedRequest.path, "/v1/hooks/claude")
        XCTAssertEqual(parsedRequest.body, Data("{}".utf8))
        XCTAssertEqual(oversizedHeaderParse, .rejected(statusCode: 431))
    }

    func testLoopbackReceiverAcceptsAuthenticatedClaudeHook() async throws {
        let activityStore = AgentActivityStore()
        let requestProcessor = makeRequestProcessor(activityStore: activityStore)
        let receiver = LocalAgentHTTPReceiver(requestProcessor: requestProcessor)
        let listeningPort = try await receiver.start()
        defer { receiver.stop() }

        let hookBody = try FixtureLoader.body(named: "session-start")
        let endpointURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(listeningPort)/v1/hooks/claude")
        )
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = hookBody
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, urlResponse) = try await URLSession.shared.data(for: urlRequest)

        XCTAssertEqual((urlResponse as? HTTPURLResponse)?.statusCode, 204)
        let agentRun = await activityStore.agentRun(identifier: "claude-session-123")
        XCTAssertEqual(agentRun?.activityState, .running)
    }

    private func makeRequestProcessor(
        activityStore: AgentActivityStore,
        maximumRequestBodyLength: Int = 65_536
    ) -> AgentBridgeRequestProcessor {
        AgentBridgeRequestProcessor(
            tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(
                expectedBearerToken: bearerToken
            ),
            activityStore: activityStore,
            maximumRequestBodyLength: maximumRequestBodyLength
        )
    }

    private func authenticatedRequest(path: String, body: Data) -> AgentBridgeRequest {
        AgentBridgeRequest(
            method: "POST",
            path: path,
            headers: [
                "Authorization": "Bearer \(bearerToken)",
                "Content-Type": "application/json"
            ],
            body: body
        )
    }
}
