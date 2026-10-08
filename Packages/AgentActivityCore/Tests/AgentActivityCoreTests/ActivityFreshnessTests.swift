import XCTest
@testable import AgentActivityCore

final class ActivityFreshnessTests: XCTestCase {
    func testInactiveObservationBecomesUnknownAndFreshActivityRecovers() async {
        let store = AgentActivityStore(activityFreshnessInterval: 300)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        await store.apply(AgentActivityEvent(agentRunIdentifier: "codex:one", providerName: .codex,
            eventKind: .runStarted, occurredAt: startedAt, summaryText: "Actual provider summary"))
        await store.reconcileActivityFreshness(at: startedAt.addingTimeInterval(299))
        var run = await store.agentRun(identifier: "codex:one")
        XCTAssertEqual(run?.activityState, .running)
        await store.reconcileActivityFreshness(at: startedAt.addingTimeInterval(300))
        run = await store.agentRun(identifier: "codex:one")
        XCTAssertEqual(run?.activityState, .unknown)
        XCTAssertEqual(run?.summaryText, "Actual provider summary")
        XCTAssertEqual(run?.lastEventAt, startedAt)
        XCTAssertFalse(run?.activityState.isConfirmedActive ?? true)
        await store.apply(AgentActivityEvent(agentRunIdentifier: "codex:one", providerName: .codex,
            eventKind: .activityChanged, occurredAt: startedAt.addingTimeInterval(301)))
        run = await store.agentRun(identifier: "codex:one")
        XCTAssertEqual(run?.activityState, .running)
    }

    func testUsageDoesNotKeepActivityAliveOrReviveUnknown() async {
        let store = AgentActivityStore(activityFreshnessInterval: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        await store.apply(AgentActivityEvent(agentRunIdentifier: "claude:one", providerName: .claude,
            eventKind: .runStarted, occurredAt: startedAt))
        await store.apply(AgentActivityEvent(agentRunIdentifier: "claude:one", providerName: .claude,
            eventKind: .usageUpdated, occurredAt: startedAt.addingTimeInterval(9)))
        await store.reconcileActivityFreshness(at: startedAt.addingTimeInterval(10))
        await store.apply(AgentActivityEvent(agentRunIdentifier: "claude:one", providerName: .claude,
            eventKind: .usageUpdated, occurredAt: startedAt.addingTimeInterval(11)))
        let run = await store.agentRun(identifier: "claude:one")
        XCTAssertEqual(run?.activityState, .unknown)
        XCTAssertEqual(run?.lastActivityAt, startedAt)
    }

    func testWaitingAttentionExpiresWithoutLosingPromptAndTerminalStatesStayTerminal() async {
        let store = AgentActivityStore(activityFreshnessInterval: 10)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        await store.apply(AgentActivityEvent(agentRunIdentifier: "waiting", providerName: .claude,
            eventKind: .attentionRequested, occurredAt: startedAt,
            attentionRequest: AgentAttentionRequest(requestIdentifier: "approval", requestKind: .approval,
                promptText: "Permission requested", canRespond: false)))
        for eventKind in [AgentActivityEventKind.runCompleted, .runFailed, .runInterrupted] {
            await store.apply(AgentActivityEvent(agentRunIdentifier: eventKind.rawValue, providerName: .codex,
                eventKind: eventKind, occurredAt: startedAt))
        }
        await store.reconcileActivityFreshness(at: startedAt.addingTimeInterval(10))
        let waitingRun = await store.agentRun(identifier: "waiting")
        XCTAssertEqual(waitingRun?.activityState, .unknown)
        XCTAssertEqual(waitingRun?.pendingAttentionRequest?.promptText, "Permission requested")
        XCTAssertFalse(waitingRun?.needsAttention ?? true)
        let runs = await store.agentRuns()
        XCTAssertEqual(Set(runs.map(\.activityState)), [.unknown, .completed, .failed, .interrupted])
    }
}
