import Foundation

public struct ClaudeQuestionOption: Equatable, Sendable {
    public let label: String
    public let description: String
}

public struct ClaudeQuestion: Equatable, Sendable {
    public let text: String
    public let header: String
    public let options: [ClaudeQuestionOption]
    public let allowsMultipleSelections: Bool
}

public struct ClaudeQuestionnaire: Equatable, Sendable {
    public let questions: [ClaudeQuestion]
    private let originalInput: [String: JSONValue]

    public init(toolInput: JSONValue) throws {
        guard case .object(let inputFields) = toolInput,
              inputFields["answers"] == nil,
              case .array(let questionInputs) = inputFields["questions"],
              (1...4).contains(questionInputs.count) else { throw ClaudePermissionError.unsupportedRequest }
        var questions: [ClaudeQuestion] = []
        for questionInput in questionInputs {
            guard let text = questionInput["question"]?.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= 2_048,
                  let header = questionInput["header"]?.stringValue, !header.isEmpty, header.utf8.count <= 64,
                  case .array(let optionInputs) = questionInput["options"], (2...4).contains(optionInputs.count) else {
                throw ClaudePermissionError.unsupportedRequest
            }
            var options: [ClaudeQuestionOption] = []
            for optionInput in optionInputs {
                guard let label = optionInput["label"]?.stringValue, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      label.utf8.count <= 256,
                      let description = optionInput["description"]?.stringValue, description.utf8.count <= 1_024,
                      optionInput["preview"] == nil else { throw ClaudePermissionError.unsupportedRequest }
                options.append(ClaudeQuestionOption(label: label, description: description))
            }
            guard Set(options.map(\.label)).count == options.count,
                  questionInput["multiSelect"] == nil || questionInput["multiSelect"] == .boolean(true) || questionInput["multiSelect"] == .boolean(false) else {
                throw ClaudePermissionError.unsupportedRequest
            }
            questions.append(ClaudeQuestion(text: text, header: header, options: options,
                                           allowsMultipleSelections: questionInput["multiSelect"] == .boolean(true)))
        }
        guard Set(questions.map(\.text)).count == questions.count,
              try JSONEncoder().encode(toolInput).count <= 8_192 else { throw ClaudePermissionError.unsupportedRequest }
        self.questions = questions
        originalInput = inputFields
    }

    public func accepts(answers: [String: String]) -> Bool {
        Set(answers.keys) == Set(questions.map(\.text))
            && answers.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4_096 }
            && answers.values.reduce(0, { $0 + $1.utf8.count }) <= 8_192
            && (try? JSONEncoder().encode(answers).count).map { $0 <= 16_384 } == true
    }

    public func hookOutput(answers: [String: String]) throws -> Data {
        guard accepts(answers: answers) else { throw ClaudePermissionError.unsupportedRequest }
        var answeredInput = originalInput
        answeredInput["answers"] = .object(answers.mapValues(JSONValue.string))
        return try JSONEncoder().encode(JSONValue.object([
            "hookSpecificOutput": .object([
                "hookEventName": .string("PreToolUse"),
                "permissionDecision": .string("allow"),
                "updatedInput": .object(answeredInput)
            ])
        ]))
    }
}
