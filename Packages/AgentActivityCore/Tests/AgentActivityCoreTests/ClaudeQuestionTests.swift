import XCTest
@testable import AgentActivityCore

final class ClaudeQuestionTests: XCTestCase {
    private let clockStart = Date(timeIntervalSince1970: 2_000)
    private let questionText = "Which format should I use?"

    func testAnswerOutputPreservesInputAndSupportsWrittenAndMultipleChoiceAnswers() throws {
        let input = questionInput()
        let questionnaire = try ClaudeQuestionnaire(toolInput: input)
        let answers = [questionText: "Use Indonesian, with short paragraphs."]
        let output = try JSONDecoder().decode(JSONValue.self, from: questionnaire.hookOutput(answers: answers))
        XCTAssertEqual(output["hookSpecificOutput"]?["hookEventName"], .string("PreToolUse"))
        XCTAssertEqual(output["hookSpecificOutput"]?["permissionDecision"], .string("allow"))
        XCTAssertEqual(output["hookSpecificOutput"]?["updatedInput"]?["questions"], input["questions"])
        XCTAssertEqual(output["hookSpecificOutput"]?["updatedInput"]?["answers"]?[questionText], .string(answers[questionText]!))
        XCTAssertNil(output["hookSpecificOutput"]?["updatedPermissions"])
        XCTAssertTrue(questionnaire.accepts(answers: [questionText: "Brief, Detailed"]))
    }

    func testEveryQuestionNeedsAnAnswerAndUnknownInputFieldsArePreserved() throws {
        guard case .array(let firstQuestions) = questionInput()["questions"],
              case .array(let secondQuestions) = questionInput(question: "Which language should I use?")["questions"] else {
            return XCTFail("Invalid question fixture")
        }
        let input = JSONValue.object([
            "questions": .array(firstQuestions + secondQuestions),
            "metadata": .object(["source": .string("provider")])
        ])
        let questionnaire = try ClaudeQuestionnaire(toolInput: input)
        XCTAssertFalse(questionnaire.accepts(answers: [questionText: "Brief"]))
        let answers = [questionText: "Detailed", "Which language should I use?": "Indonesian"]
        let output = try JSONDecoder().decode(JSONValue.self, from: questionnaire.hookOutput(answers: answers))
        XCTAssertEqual(output["hookSpecificOutput"]?["updatedInput"]?["metadata"], input["metadata"])
        XCTAssertEqual(output["hookSpecificOutput"]?["updatedInput"]?["answers"]?["Which language should I use?"], .string("Indonesian"))
        var unexpectedAnswers = answers
        unexpectedAnswers["A different question"] = "Should not be submitted"
        XCTAssertFalse(questionnaire.accepts(answers: unexpectedAnswers))
    }

    func testQuestionValidationRejectsAmbiguousUnsupportedAndOversizedForms() throws {
        let validInput = questionInput()
        for invalidInput in [JSONValue.object([:]), questionInput(question: String(repeating: "x", count: 2_049))] {
            XCTAssertThrowsError(try ClaudeQuestionnaire(toolInput: invalidInput))
        }
        guard case .array(let questions) = validInput["questions"], case .object(var question) = questions[0],
              case .array(var options) = question["options"], case .object(var option) = options[0] else { return XCTFail("Invalid fixture") }
        option["preview"] = .string("<p>Preview content</p>")
        options[0] = .object(option)
        question["options"] = .array(options)
        XCTAssertThrowsError(try ClaudeQuestionnaire(toolInput: .object(["questions": .array([.object(question)])])))
        XCTAssertThrowsError(try ClaudeQuestionnaire(toolInput: .object(["questions": .array(questions + questions)])))
        let questionnaire = try ClaudeQuestionnaire(toolInput: validInput)
        for answers in [[:], [questionText: "  "], ["another question": "Brief"], [questionText: String(repeating: "x", count: 4_097)]] {
            XCTAssertFalse(questionnaire.accepts(answers: answers))
        }
    }

    func testNativeAnswerIsSingleUseAndCannotApproveOtherTools() async throws {
        let activity = AgentActivityStore()
        let interactions = ClaudePermissionStore(activityStore: activity)
        let registration = try await interactions.register(hookBody: hook(), at: clockStart)
        let requests = await interactions.requests(at: clockStart)
        let request = try XCTUnwrap(requests.first)
        XCTAssertNotNil(request.questionnaire)
        let run = await activity.agentRun(identifier: request.agentRunIdentifier)
        XCTAssertEqual(run?.activityState, .waitingForUser)
        let permission = await interactions.decide(.allow, requestIdentifier: request.id, at: clockStart)
        XCTAssertFalse(permission)
        let incomplete = await interactions.answerQuestions([:], requestIdentifier: request.id, at: clockStart)
        XCTAssertFalse(incomplete)
        let answers = [questionText: "Detailed"]
        let accepted = await interactions.answerQuestions(answers, requestIdentifier: request.id, at: clockStart)
        XCTAssertTrue(accepted)
        let duplicate = await interactions.answerQuestions([questionText: "Brief"], requestIdentifier: request.id, at: clockStart)
        XCTAssertFalse(duplicate)
        let poll = await interactions.poll(requestIdentifier: registration.requestIdentifier, at: clockStart)
        XCTAssertEqual(poll?.answers, answers)
        XCTAssertNil(poll?.decision)
        let replay = await interactions.poll(requestIdentifier: request.id, at: clockStart)
        XCTAssertNil(replay)
    }

    func testQuestionExpiryPollingLossReplacementAndReturnToClaude() async throws {
        let interactions = ClaudePermissionStore(activityStore: AgentActivityStore())
        let replaced = try await interactions.register(hookBody: hook(), at: clockStart)
        let registration = try await interactions.register(hookBody: hook(), at: clockStart)
        let staleAnswer = await interactions.answerQuestions([questionText: "Brief"], requestIdentifier: replaced.requestIdentifier, at: clockStart)
        XCTAssertFalse(staleAnswer)
        for second in stride(from: 2, through: 178, by: 2) {
            _ = await interactions.poll(requestIdentifier: registration.requestIdentifier, at: clockStart.addingTimeInterval(Double(second)))
        }
        let expired = await interactions.answerQuestions([questionText: "Brief"], requestIdentifier: registration.requestIdentifier, at: clockStart.addingTimeInterval(180))
        XCTAssertFalse(expired)
        let fresh = try await interactions.register(hookBody: hook(), at: clockStart)
        let returned = await interactions.returnQuestionsToClaude(requestIdentifier: fresh.requestIdentifier, at: clockStart)
        XCTAssertTrue(returned)
        let afterReturn = await interactions.poll(requestIdentifier: fresh.requestIdentifier, at: clockStart)
        XCTAssertNil(afterReturn)
        let lostPolling = try await interactions.register(hookBody: hook(), at: clockStart)
        let lostAnswer = await interactions.answerQuestions([questionText: "Brief"], requestIdentifier: lostPolling.requestIdentifier, at: clockStart.addingTimeInterval(3))
        XCTAssertFalse(lostAnswer)
        await interactions.removeAll()
        let afterRestart = await interactions.requests(at: clockStart)
        XCTAssertTrue(afterRestart.isEmpty)
    }

    func testQuestionLoopbackRequiresAuthenticationAndHasNoAnswerEndpoint() async throws {
        let activity = AgentActivityStore()
        let interactions = ClaudePermissionStore(activityStore: activity)
        let processor = AgentBridgeRequestProcessor(tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(expectedBearerToken: "fixture"), activityStore: activity, permissionStore: interactions)
        let receiver = LocalAgentHTTPReceiver(requestProcessor: processor)
        let port = try await receiver.start()
        defer { receiver.stop() }
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/claude/approvals"))
        let questionTask = Task { await ClaudePermissionClient(endpoint: endpoint).requestAnswers(hookBody: hook(), bearerToken: "fixture") }
        var waitingRequest: ClaudePermissionRequest?
        for _ in 0..<50 {
            waitingRequest = await interactions.requests().first
            if waitingRequest != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let request = try XCTUnwrap(waitingRequest)
        let unauthorized = await processor.process(AgentBridgeRequest(method: "POST", path: "/v1/claude/approvals", headers: ["Content-Type": "application/json"], body: hook()))
        XCTAssertEqual(unauthorized.statusCode, 401)
        let remoteAnswer = await processor.process(AgentBridgeRequest(method: "POST", path: "/v1/claude/approvals/\(request.id)/answers", headers: ["Authorization": "Bearer fixture", "Content-Type": "application/json"], body: Data("{}".utf8)))
        XCTAssertEqual(remoteAnswer.statusCode, 404)
        let accepted = await interactions.answerQuestions([questionText: "From the notch"], requestIdentifier: request.id)
        XCTAssertTrue(accepted)
        let answer = await questionTask.value
        XCTAssertEqual(answer, [questionText: "From the notch"])
    }

    func testQuestionContentAndAnswersStayOutOfActivityAndLifecycleCancelsTheTicket() async throws {
        let activity = AgentActivityStore()
        let interactions = ClaudePermissionStore(activityStore: activity)
        let registration = try await interactions.register(hookBody: hook(), at: clockStart)
        let requests = await interactions.requests(at: clockStart)
        let request = try XCTUnwrap(requests.first)
        let accepted = await interactions.answerQuestions([questionText: "Private written answer"], requestIdentifier: request.id, at: clockStart)
        XCTAssertTrue(accepted)
        let runs = await activity.agentRuns()
        let snapshot = String(decoding: try JSONEncoder().encode(runs), as: UTF8.self)
        XCTAssertFalse(snapshot.contains(questionText))
        XCTAssertFalse(snapshot.contains("Private written answer"))
        let usage = await interactions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .usageUpdated))
        XCTAssertTrue(usage)
        let notification = await interactions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .attentionRequested, providerEventName: "Notification"))
        XCTAssertFalse(notification)
        _ = await interactions.observe(AgentActivityEvent(agentRunIdentifier: request.agentRunIdentifier, providerName: .claude, eventKind: .runCompleted))
        let canceled = await interactions.poll(requestIdentifier: registration.requestIdentifier, at: clockStart)
        XCTAssertNil(canceled)
    }

    private func questionInput(question: String? = nil) -> JSONValue {
        .object(["questions": .array([.object([
            "question": .string(question ?? questionText), "header": .string("Format"), "multiSelect": .boolean(false),
            "options": .array([
                .object(["label": .string("Brief"), "description": .string("Short summary")]),
                .object(["label": .string("Detailed"), "description": .string("Full explanation")])
            ])
        ])])])
    }

    private func hook() -> Data {
        try! JSONEncoder().encode(JSONValue.object([
            "session_id": .string("question-fixture"), "cwd": .string("/tmp/notch-question-fixture"),
            "hook_event_name": .string("PreToolUse"), "tool_name": .string("AskUserQuestion"),
            "tool_use_id": .string("question-tool"), "tool_input": questionInput()
        ]))
    }
}
