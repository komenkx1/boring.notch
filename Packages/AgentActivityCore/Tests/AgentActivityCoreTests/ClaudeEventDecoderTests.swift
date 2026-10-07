import XCTest
@testable import AgentActivityCore

final class ClaudeEventDecoderTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_791_000_000)

    func testSessionStartCreatesRunningLifecycleEvent() throws {
        let hookBody = try FixtureLoader.body(named: "session-start")

        let event = try ClaudeHookEventDecoder().decodeEvent(
            from: hookBody,
            receivedAt: receivedAt
        )

        XCTAssertEqual(event.agentRunIdentifier, "claude-session-123")
        XCTAssertEqual(event.providerName, .claude)
        XCTAssertEqual(event.eventKind, .runStarted)
        XCTAssertEqual(event.workingDirectory, "/tmp/agent-project")
        XCTAssertEqual(event.repositoryLabel, "agent-project")
        XCTAssertEqual(event.providerEventName, "SessionStart")
        XCTAssertEqual(event.occurredAt, receivedAt)
    }

    func testPermissionRequestCreatesObservationalAttentionEvent() throws {
        let hookBody = try FixtureLoader.body(named: "permission-request")

        let event = try ClaudeHookEventDecoder().decodeEvent(from: hookBody)

        XCTAssertEqual(event.eventKind, .attentionRequested)
        XCTAssertEqual(event.summaryText, "Run the project test suite")
        XCTAssertEqual(event.attentionRequest?.requestKind, .approval)
        XCTAssertEqual(event.attentionRequest?.canRespond, false)
        XCTAssertEqual(
            event.attentionRequest?.requestIdentifier,
            "permission:claude-session-123:turn-456"
        )
    }

    func testPermissionNotificationCreatesApprovalAttentionEvent() throws {
        let hookBody = try FixtureLoader.body(named: "notification-permission")

        let event = try ClaudeHookEventDecoder().decodeEvent(from: hookBody)

        XCTAssertEqual(event.eventKind, .attentionRequested)
        XCTAssertEqual(event.summaryText, "Claude needs your permission")
        XCTAssertEqual(event.attentionRequest?.requestKind, .approval)
        XCTAssertEqual(event.attentionRequest?.canRespond, false)
    }

    func testMessageDisplayPreservesMessageIdentifierForStreamingAssembly() throws {
        let hookBody = try FixtureLoader.body(named: "message-display-first")

        let event = try ClaudeHookEventDecoder().decodeEvent(from: hookBody)

        XCTAssertEqual(event.eventKind, .activityChanged)
        XCTAssertEqual(event.summaryText, "Tests are ")
        XCTAssertEqual(event.providerEventName, "MessageDisplay")
        XCTAssertEqual(event.providerEventIdentifier, "message-789")
    }

    func testStatusSnapshotMapsDocumentedUsageWindows() throws {
        let statusBody = try FixtureLoader.body(named: "status-line")

        let event = try ClaudeStatusSnapshotDecoder().decodeEvent(
            from: statusBody,
            receivedAt: receivedAt
        )

        XCTAssertEqual(event.eventKind, .usageUpdated)
        XCTAssertEqual(event.modelLabel, "Claude Sonnet 4.5")
        XCTAssertEqual(event.usageWindows.count, 4)
        XCTAssertEqual(event.usageWindows[0].windowLabel, "Context window")
        XCTAssertEqual(event.usageWindows[0].usedPercentage, 37.5)
        XCTAssertEqual(event.usageWindows[1].windowDurationMinutes, 300)
        XCTAssertEqual(event.usageWindows[2].windowDurationMinutes, 10_080)
        XCTAssertEqual(event.usageWindows[3].usedPercentage, 112.0)
    }
}
