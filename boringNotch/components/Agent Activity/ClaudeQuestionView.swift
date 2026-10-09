import AgentActivityCore
import SwiftUI

struct ClaudeQuestionView: View {
    let request: ClaudePermissionRequest
    let questionnaire: ClaudeQuestionnaire
    let revealField: (String) -> Void
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var runtime = AgentActivityRuntime.shared
    @State private var selectedLabels: [Int: Set<String>] = [:]
    @State private var writtenAnswers: [Int: String] = [:]
    @State private var submitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: String?

    private var answers: [String: String] {
        var answersByQuestion: [String: String] = [:]
        for (index, question) in questionnaire.questions.enumerated() {
            let writtenAnswer = writtenAnswers[index, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedAnswer = question.options.map(\.label).filter { selectedLabels[index, default: []].contains($0) }.joined(separator: ", ")
            answersByQuestion[question.text] = writtenAnswer.isEmpty ? selectedAnswer : writtenAnswer
        }
        return answersByQuestion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude needs your answer")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AgentActivityColor.attention)
            Text(request.workingDirectory)
                .font(.system(size: 10))
                .foregroundStyle(AgentActivityColor.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if request.answers != nil {
                Text("Answers recorded. Waiting for the Claude hook.")
                    .font(.system(size: 11)).foregroundStyle(.white)
            } else {
                ForEach(questionnaire.questions.indices, id: \.self) { index in
                    questionFields(at: index)
                }
                Text("Typed text replaces the selected options. Answer every question, then send. After 3 minutes, respond in Claude.")
                    .font(.system(size: 10))
                    .foregroundStyle(AgentActivityColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    actionButton("Answer in Claude", focus: "question-actions-later") { submit(returnToClaude: true) }
                    actionButton("Send answers", focus: "question-actions-send") { submit(returnToClaude: false) }
                        .disabled(!questionnaire.accepts(answers: answers))
                }
                .id("question-actions")
            }
            if submitting {
                Text("Recording answers…").font(.system(size: 11)).foregroundStyle(.white)
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.white)
            }
        }
        .disabled(submitting || request.answers != nil)
        .onChange(of: focusedField) {
            vm.isEditingAgentAnswer = focusedField != nil
            if let focusedField {
                if focusedField.hasPrefix("question-actions") { revealField("question-actions") }
                else if let questionIndex = focusedField.split(separator: ":").first { revealField(String(questionIndex)) }
            }
        }
        .onDisappear { vm.isEditingAgentAnswer = false }
    }

    private func questionFields(at index: Int) -> some View {
        let question = questionnaire.questions[index]
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1) of \(questionnaire.questions.count) · \(question.header)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AgentActivityColor.secondaryText)
            Text(question.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if question.allowsMultipleSelections {
                Text("Select one or more options.").font(.system(size: 10)).foregroundStyle(AgentActivityColor.secondaryText)
            }
            ForEach(question.options.indices, id: \.self) { optionIndex in
                optionButton(question.options[optionIndex], questionIndex: index, optionIndex: optionIndex)
            }
            TextField("", text: Binding(get: { writtenAnswers[index, default: ""] }, set: { writtenAnswers[index] = $0 }),
                      prompt: Text("Or type your answer").foregroundStyle(AgentActivityColor.secondaryText), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .padding(10)
                .frame(minHeight: 44)
                .background(AgentActivityColor.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { focusBorder(for: "question-\(index):text") }
                .focused($focusedField, equals: "question-\(index):text")
                .accessibilityLabel("Your answer: \(question.text)")
        }
        .id("question-\(index)")
    }

    private func optionButton(_ option: ClaudeQuestionOption, questionIndex: Int, optionIndex: Int) -> some View {
        let selected = selectedLabels[questionIndex, default: []].contains(option.label)
        let focus = "question-\(questionIndex):option-\(optionIndex)"
        return Button {
            select(option.label, questionIndex: questionIndex)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 11, weight: .semibold))
                    Text(option.description).font(.system(size: 10)).foregroundStyle(AgentActivityColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? AgentActivityColor.selectedSurface : AgentActivityColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { focusBorder(for: focus) }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedField, equals: focus)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .onKeyPress(keys: [.space, .return]) { _ in
            select(option.label, questionIndex: questionIndex)
            return .handled
        }
    }

    private func select(_ label: String, questionIndex: Int) {
        guard !submitting, request.answers == nil else { return }
        if questionnaire.questions[questionIndex].allowsMultipleSelections {
            if selectedLabels[questionIndex, default: []].contains(label) { selectedLabels[questionIndex]?.remove(label) }
            else { selectedLabels[questionIndex, default: []].insert(label) }
        } else { selectedLabels[questionIndex] = [label] }
    }

    private func actionButton(_ title: String, focus: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(AgentActivityColor.selectedSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay { focusBorder(for: focus) }
            .focusable()
            .focused($focusedField, equals: focus)
            .onKeyPress(keys: [.space, .return]) { _ in
                guard !submitting else { return .ignored }
                action()
                return .handled
            }
    }

    private func focusBorder(for field: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(focusedField == field ? Color.white : AgentActivityColor.secondaryText, lineWidth: 2)
    }

    private func submit(returnToClaude: Bool) {
        guard !submitting, request.answers == nil,
              returnToClaude || questionnaire.accepts(answers: answers) else { return }
        submitting = true
        errorMessage = nil
        let submittedAnswers = answers
        Task { @MainActor in
            let accepted = returnToClaude
                ? await runtime.returnQuestionsToClaude(requestIdentifier: request.id)
                : await runtime.answerClaudeQuestions(submittedAnswers, requestIdentifier: request.id)
            if !accepted { errorMessage = "This question is no longer available. Respond in Claude." }
            submitting = false
        }
    }
}
