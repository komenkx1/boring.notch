import XCTest
@testable import AgentActivityCore

final class ClaudePermissionTests: XCTestCase {
    private let clockStart = Date(timeIntervalSince1970: 1_000)

    func testDecisionIsBoundToRequestAndConsumedOnlyOnce() async throws {
        let activity = AgentActivityStore()
        let permissions = ClaudePermissionStore(activityStore: activity)
        let first = try await permissions.register(hookBody: hook(), at: clockStart)
        let other = try await permissions.register(hookBody: hook(session: "other"), at: clockStart)
        let wrongIdentifier = await permissions.decide(.allow, requestIdentifier: UUID(), at: clockStart)
        XCTAssertFalse(wrongIdentifier)
        let accepted = await permissions.decide(.allow, requestIdentifier: first.requestIdentifier, at: clockStart)
        XCTAssertTrue(accepted)
        let duplicate = await permissions.decide(.deny, requestIdentifier: first.requestIdentifier, at: clockStart)
        XCTAssertFalse(duplicate)
        let answer = await permissions.poll(requestIdentifier: first.requestIdentifier, at: clockStart)
        XCTAssertEqual(answer?.decision, .allow)
        let replay = await permissions.poll(requestIdentifier: first.requestIdentifier, at: clockStart)
        XCTAssertNil(replay)
        let unanswered = await permissions.poll(requestIdentifier: other.requestIdentifier, at: clockStart)
        XCTAssertNotNil(unanswered)
        XCTAssertNil(unanswered?.decision)
    }

    func testReplacementExpiryLostPollingAndRestartNeverAllow() async throws {
        let permissions = ClaudePermissionStore(activityStore: AgentActivityStore())
        let replaced = try await permissions.register(hookBody: hook(), at: clockStart)
        let current = try await permissions.register(hookBody: hook(), at: clockStart)
        let oldDecision = await permissions.decide(.allow, requestIdentifier: replaced.requestIdentifier, at: clockStart)
        XCTAssertFalse(oldDecision)
        let stale = await permissions.decide(.allow, requestIdentifier: current.requestIdentifier, at: clockStart.addingTimeInterval(3))
        XCTAssertFalse(stale)
        let expiring = try await permissions.register(hookBody: hook(), at: clockStart)
        for second in stride(from: 2, through: 44, by: 2) {
            _ = await permissions.poll(requestIdentifier: expiring.requestIdentifier, at: clockStart.addingTimeInterval(Double(second)))
        }
        let expired = await permissions.decide(.allow, requestIdentifier: expiring.requestIdentifier, at: clockStart.addingTimeInterval(45))
        XCTAssertFalse(expired)
        await permissions.removeAll()
        let afterRestart = await permissions.poll(requestIdentifier: expiring.requestIdentifier, at: clockStart)
        XCTAssertNil(afterRestart)
    }

    func testLifecycleCancelsButUsageAndNotificationPreservePendingRequest() async throws {
        let activity = AgentActivityStore()
        let permissions = ClaudePermissionStore(activityStore: activity)
        let registration = try await permissions.register(hookBody: hook(), at: clockStart)
        let requests = await permissions.requests(at: clockStart)
        let request = try XCTUnwrap(requests.first)
        let usage = await permissions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .usageUpdated))
        XCTAssertTrue(usage)
        let notification = await permissions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .attentionRequested, providerEventName: "Notification"))
        XCTAssertFalse(notification)
        _ = await permissions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .runCompleted))
        let answer = await permissions.decide(.allow, requestIdentifier: registration.requestIdentifier, at: clockStart)
        XCTAssertFalse(answer)
    }

    func testUnsupportedAndOversizedRequestsFallBackWithoutTicket() async throws {
        let permissions = ClaudePermissionStore(activityStore: AgentActivityStore())
        for body in [hook(tool: "AskUserQuestion"), hook(command: String(repeating: "x", count: 8_193)), Data("{}".utf8)] {
            do {
                _ = try await permissions.register(hookBody: body, at: clockStart)
                XCTFail("Unsupported request must not become interactive")
            } catch {}
        }
        let requests = await permissions.requests(at: clockStart)
        XCTAssertTrue(requests.isEmpty)
    }

    func testTicketCapacityIsBoundedAndClearedOnRestart() async throws {
        let permissions = ClaudePermissionStore(activityStore: AgentActivityStore())
        for sessionNumber in 0..<16 {
            _ = try await permissions.register(hookBody: hook(session: "session-\(sessionNumber)"), at: clockStart)
        }
        do {
            _ = try await permissions.register(hookBody: hook(session: "seventeenth"), at: clockStart)
            XCTFail("Ticket capacity must be enforced")
        } catch ClaudePermissionError.tooManyRequests {}
        let requests = await permissions.requests(at: clockStart)
        XCTAssertEqual(requests.count, 16)
        await permissions.removeAll()
        let clearedRequests = await permissions.requests(at: clockStart)
        XCTAssertTrue(clearedRequests.isEmpty)
    }

    func testLoopbackClientReturnsOnlyNativeDecisionAndHTTPCannotApprove() async throws {
        let activity = AgentActivityStore()
        let permissions = ClaudePermissionStore(activityStore: activity)
        let processor = AgentBridgeRequestProcessor(tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(expectedBearerToken: "fixture"), activityStore: activity, permissionStore: permissions)
        let receiver = LocalAgentHTTPReceiver(requestProcessor: processor)
        let port = try await receiver.start()
        defer { receiver.stop() }
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/claude/approvals"))
        let clientTask = Task { await ClaudePermissionClient(endpoint: endpoint).requestDecision(hookBody: hook(), bearerToken: "fixture") }
        var request: ClaudePermissionRequest?
        for _ in 0..<50 {
            request = await permissions.requests().first
            if request != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let waitingRequest = try XCTUnwrap(request)
        let response = await processor.process(AgentBridgeRequest(method: "POST", path: "/v1/claude/approvals/\(waitingRequest.id)/decision", headers: ["Authorization": "Bearer fixture", "Content-Type": "application/json"], body: Data("{\"decision\":\"allow\"}".utf8)))
        XCTAssertEqual(response.statusCode, 404)
        let unauthenticated = await processor.process(AgentBridgeRequest(method: "POST", path: "/v1/claude/approvals", headers: ["Content-Type": "application/json"], body: hook()))
        XCTAssertEqual(unauthenticated.statusCode, 401)
        let denied = await permissions.decide(.deny, requestIdentifier: waitingRequest.id)
        XCTAssertTrue(denied)
        let clientDecision = await clientTask.value
        XCTAssertEqual(clientDecision, .deny)
        let output = try JSONDecoder().decode(JSONValue.self, from: ClaudePermissionDecision.allow.hookOutput())
        XCTAssertEqual(output["hookSpecificOutput"]?["decision"]?["behavior"], .string("allow"))
        XCTAssertNil(output["hookSpecificOutput"]?["decision"]?["updatedPermissions"])
        XCTAssertNil(output["hookSpecificOutput"]?["decision"]?["updatedInput"])
        let wrongToken = await ClaudePermissionClient(endpoint: endpoint).requestDecision(hookBody: hook(), bearerToken: "wrong")
        XCTAssertNil(wrongToken)
    }

    private func hook(session: String = "approval-test", tool: String = "Bash", command: String = "printf 'notch approval test'") -> Data {
        try! JSONEncoder().encode(JSONValue.object([
            "session_id": .string(session), "cwd": .string("/tmp/notch-approval-test"),
            "hook_event_name": .string("PermissionRequest"), "tool_name": .string(tool),
            "tool_input": .object(["command": .string(command)])
        ]))
    }
}
