import XCTest
@testable import AgentActivityCore

final class CodexIntegrationTests: XCTestCase {
    func testAuthenticatedCodexEndpointAndMalformedEvent() async {
        let store = AgentActivityStore()
        let processor = AgentBridgeRequestProcessor(
            tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(expectedBearerToken: "test"),
            activityStore: store
        )
        let request = AgentBridgeRequest(method: "POST", path: "/v1/hooks/codex",
            headers: ["Authorization": "Bearer test", "Content-Type": "application/json"],
            body: Data(#"{"session_id":"test","hook_event_name":"SessionStart"}"#.utf8))
        let accepted = await processor.process(request)
        XCTAssertEqual(accepted.statusCode, 204)
        let rejected = await processor.process(AgentBridgeRequest(method: "POST", path: request.path,
            headers: request.headers, body: Data("{}".utf8)))
        XCTAssertEqual(rejected.statusCode, 400)
        let unauthorized = await processor.process(AgentBridgeRequest(method: "POST", path: request.path,
            headers: ["Content-Type": "application/json"], body: request.body))
        XCTAssertEqual(unauthorized.statusCode, 401)
    }

    func testLifecycleKeepsFinalResponseAfterSessionEnd() async throws {
        let store = AgentActivityStore()
        let decoder = CodexHookEventDecoder()
        let events = [
            #"{"session_id":"test","hook_event_name":"SessionStart","model":"gpt-test","cwd":"/work/project"}"#,
            #"{"session_id":"test","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#,
            #"{"session_id":"test","hook_event_name":"Stop","last_assistant_message":"Finished verification"}"#,
            #"{"session_id":"test","hook_event_name":"SessionEnd"}"#
        ]
        for eventJSON in events {
            await store.apply(try decoder.decodeEvent(from: Data(eventJSON.utf8)))
        }
        let run = await store.agentRun(identifier: "codex:test")
        XCTAssertEqual(run?.providerName, .codex)
        XCTAssertEqual(run?.activityState, .completed)
        XCTAssertEqual(run?.summaryText, "Finished verification")
        XCTAssertEqual(run?.modelLabel, "gpt-test")
        XCTAssertNil(run?.pendingAttentionRequest)
        XCTAssertEqual(run?.usageWindows, [])
    }

    func testPermissionIsObservationalAndSubagentHasSeparateIdentity() throws {
        let event = try CodexHookEventDecoder().decodeEvent(from: Data(#"{"session_id":"test","agent_id":"child","hook_event_name":"PermissionRequest","tool_name":"Bash","prompt":"private prompt"}"#.utf8))
        XCTAssertEqual(event.agentRunIdentifier, "codex:test:agent:child")
        XCTAssertEqual(event.attentionRequest?.canRespond, false)
        XCTAssertFalse(event.summaryText?.contains("private prompt") ?? true)
        XCTAssertThrowsError(try CodexHookEventDecoder().decodeEvent(from: Data(#"{"session_id":"test","hook_event_name":"Unknown"}"#.utf8)))
    }

    func testInstallerPreservesExistingHooksAndIsReversible() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = CodexIntegrationSettingsManager(codexDirectory: directory)
        let existing = Data(#"{"custom":true,"hooks":{"Stop":[],"Interrupt":[{"hooks":[]}],"SessionStart":[{"command":"legacy-command"},{"hooks":[{"type":"command","command":"existing-command"}]}]}}"#.utf8)
        try existing.write(to: manager.hooksFile)
        _ = try manager.preview()
        XCTAssertEqual(try Data(contentsOf: manager.hooksFile), existing)
        try manager.install(executableBytes: Data("test executable".utf8))
        let firstInstall = try Data(contentsOf: manager.hooksFile)
        try manager.install(executableBytes: Data("test executable".utf8))
        XCTAssertEqual(try Data(contentsOf: manager.hooksFile), firstInstall)
        try manager.uninstall()
        let remaining = try JSONSerialization.jsonObject(with: Data(contentsOf: manager.hooksFile)) as! NSDictionary
        let original = try JSONSerialization.jsonObject(with: existing) as! NSDictionary
        XCTAssertEqual(remaining, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.forwardingExecutable.path))
    }
}
