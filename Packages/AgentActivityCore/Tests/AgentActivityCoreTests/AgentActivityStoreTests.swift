import XCTest
@testable import AgentActivityCore

final class AgentActivityStoreTests: XCTestCase {
    func testClaudeLifecycleAggregatesResponseAndClearsAttention() async throws {
        let activityStore = AgentActivityStore()
        let hookDecoder = ClaudeHookEventDecoder()
        let activeFixtureNames = [
            "session-start",
            "permission-request",
            "message-display-first",
            "message-display-final"
        ]

        for (fixtureIndex, fixtureName) in activeFixtureNames.enumerated() {
            let hookBody = try FixtureLoader.body(named: fixtureName)
            let normalizedEvent = try hookDecoder.decodeEvent(
                from: hookBody,
                receivedAt: Date(timeIntervalSince1970: Double(fixtureIndex + 1))
            )
            await activityStore.apply(normalizedEvent)
        }

        let activeRun = await activityStore.agentRun(identifier: "claude-session-123")
        XCTAssertEqual(activeRun?.activityState, .running)
        XCTAssertNil(activeRun?.pendingAttentionRequest)
        XCTAssertEqual(activeRun?.latestAssistantResponse, "Tests are passing.")

        let stopBody = try FixtureLoader.body(named: "stop")
        let stopEvent = try hookDecoder.decodeEvent(
            from: stopBody,
            receivedAt: Date(timeIntervalSince1970: 5)
        )
        await activityStore.apply(stopEvent)

        let completedRun = await activityStore.agentRun(identifier: "claude-session-123")
        XCTAssertEqual(completedRun?.activityState, .completed)
        XCTAssertEqual(completedRun?.summaryText, "Tests are passing.")
    }

    func testDuplicateAndOlderEventsDoNotReplaceCurrentState() async {
        let activityStore = AgentActivityStore()
        let firstEventIdentifier = UUID()
        let recentEvent = AgentActivityEvent(
            eventIdentifier: firstEventIdentifier,
            agentRunIdentifier: "claude-session",
            providerName: .claude,
            eventKind: .activityChanged,
            occurredAt: Date(timeIntervalSince1970: 20),
            summaryText: "Using Bash"
        )
        let olderEvent = AgentActivityEvent(
            agentRunIdentifier: "claude-session",
            providerName: .claude,
            eventKind: .runFailed,
            occurredAt: Date(timeIntervalSince1970: 10),
            summaryText: "Old failure"
        )

        let firstApplication = await activityStore.apply(recentEvent)
        let duplicateApplication = await activityStore.apply(recentEvent)
        let olderApplication = await activityStore.apply(olderEvent)

        XCTAssertEqual(firstApplication, .applied)
        XCTAssertEqual(duplicateApplication, .ignoredDuplicate)
        XCTAssertEqual(olderApplication, .ignoredStale)
        let agentRun = await activityStore.agentRun(identifier: "claude-session")
        XCTAssertEqual(agentRun?.activityState, .running)
        XCTAssertEqual(agentRun?.summaryText, "Using Bash")
    }
}
