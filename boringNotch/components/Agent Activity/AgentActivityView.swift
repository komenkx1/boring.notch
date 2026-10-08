import AgentActivityCore
import SwiftUI

enum AgentActivityColor {
    static let attention = Color(red: 1.0, green: 0.69, blue: 0.13)
    static let running = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let failed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let secondaryText = Color(red: 0.70, green: 0.70, blue: 0.70)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let selectedSurface = Color(red: 0.16, green: 0.16, blue: 0.16)
}

extension AgentActivityState {
    var isActive: Bool {
        isConfirmedActive
    }

    var label: String {
        switch self {
        case .starting: "Starting"
        case .running: "Running"
        case .waitingForApproval: "Approval needed"
        case .waitingForUser: "Waiting for input"
        case .completed: "Completed"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        case .unknown: "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .starting: "ellipsis.circle.fill"
        case .running: "play.circle.fill"
        case .waitingForApproval: "exclamationmark.triangle.fill"
        case .waitingForUser: "questionmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .interrupted: "stop.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .starting, .running:
            AgentActivityColor.running
        case .waitingForApproval, .waitingForUser:
            AgentActivityColor.attention
        case .failed:
            AgentActivityColor.failed
        case .completed, .interrupted, .unknown:
            AgentActivityColor.secondaryText
        }
    }
}

struct AgentActivityView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var agentActivityRuntime = AgentActivityRuntime.shared
    @State private var selectedAgentRunIdentifier: String?

    private var selectedAgentRun: AgentRun? {
        if let selectedAgentRunIdentifier,
           let selectedAgentRun = agentActivityRuntime.agentRuns.first(where: {
               $0.agentRunIdentifier == selectedAgentRunIdentifier
           }) {
            return selectedAgentRun
        }
        return agentActivityRuntime.agentRuns.first
    }

    var body: some View {
        Group {
            switch agentActivityRuntime.bridgeAvailability {
            case .starting:
                AgentActivityMessageView(
                    systemImage: "clock",
                    title: "Starting agent monitor",
                    message: "Connecting to the local agent bridge."
                )
            case .unavailable:
                AgentActivityUnavailableView {
                    agentActivityRuntime.retry()
                }
            case .listening:
                if agentActivityRuntime.agentRuns.isEmpty {
                    AgentActivityMessageView(
                        systemImage: "terminal",
                        title: "No agent sessions yet",
                        message: "Start an integrated Claude or Codex session to see activity here."
                    )
                } else {
                    activityContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectHighestPriorityRun()
        }
        .onChange(of: agentActivityRuntime.agentRuns.map(\.agentRunIdentifier)) {
            selectHighestPriorityRunIfNeeded()
        }
        .onExitCommand {
            vm.close()
        }
        .onDisappear {
            if let notchWindow = NSApp.keyWindow as? BoringNotchSkyLightWindow {
                notchWindow.resignKey()
            }
        }
    }

    private var activityContent: some View {
        HStack(spacing: 12) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 5) {
                    ForEach(agentActivityRuntime.agentRuns) { agentRun in
                        AgentRunRow(
                            agentRun: agentRun,
                            selected: agentRun.agentRunIdentifier == selectedAgentRun?.agentRunIdentifier
                        ) {
                            selectedAgentRunIdentifier = agentRun.agentRunIdentifier
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
            .frame(width: 190)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1)

            if let selectedAgentRun {
                ScrollView(.vertical) {
                    AgentRunDetail(agentRun: selectedAgentRun)
                }
                .scrollIndicators(.never)
                .id(selectedAgentRun.agentRunIdentifier)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

    private func selectHighestPriorityRun() {
        selectedAgentRunIdentifier = agentActivityRuntime.agentRuns.first?.agentRunIdentifier
    }

    private func selectHighestPriorityRunIfNeeded() {
        guard let selectedAgentRunIdentifier,
              agentActivityRuntime.agentRuns.contains(where: {
                  $0.agentRunIdentifier == selectedAgentRunIdentifier
              }) else {
            selectHighestPriorityRun()
            return
        }
    }
}

private struct AgentRunRow: View {
    let agentRun: AgentRun
    let selected: Bool
    let action: () -> Void

    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: agentRun.activityState.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(agentRun.activityState.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agentRun.repositoryLabel ?? "\(agentRun.providerName.displayName) session")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(agentRun.providerName.displayName) · \(agentRun.activityState.label)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AgentActivityColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 41)
            .background(
                selected ? AgentActivityColor.selectedSurface : AgentActivityColor.surface,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(hasKeyboardFocus ? Color.white : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($hasKeyboardFocus)
        .accessibilityLabel(
            "\(agentRun.providerName.displayName), \(agentRun.repositoryLabel ?? "session"), \(agentRun.activityState.label)"
        )
    }
}

private struct AgentRunDetail: View {
    let agentRun: AgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(agentRun.providerName.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(agentRun.activityState.color)
                    Text(agentRun.modelLabel ?? "Model unavailable")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AgentActivityColor.secondaryText)
                }

                Spacer()

                Label(agentRun.activityState.label, systemImage: agentRun.activityState.systemImage)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(agentRun.activityState.color)
            }

            Text(agentRun.summaryText ?? fallbackSummary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

            if agentRun.activityState == .unknown {
                Text("No recent activity event. Check the session in \(agentRun.providerName.displayName).")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentActivityColor.secondaryText)
            } else if agentRun.needsAttention {
                Text("Respond in \(agentRun.providerName.displayName) to continue this session.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentActivityColor.attention)
            }

            if agentRun.providerName == .codex {
                CodexAccountUsageView()
            } else if agentRun.usageWindows.isEmpty {
                Text("Usage unavailable for this session")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentActivityColor.secondaryText)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(agentRun.usageWindows, id: \.windowLabel) { usageWindow in
                            AgentUsageMeter(usageWindow: usageWindow)
                        }
                    }
                }
                .scrollIndicators(.never)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var fallbackSummary: String {
        let providerName = agentRun.providerName.displayName
        switch agentRun.activityState {
        case .starting:
            return "\(providerName) is starting this session."
        case .running:
            return "\(providerName) is working."
        case .waitingForApproval:
            return "\(providerName) needs permission before it can continue."
        case .waitingForUser:
            return "\(providerName) is waiting for your input."
        case .completed:
            return "\(providerName) finished this session."
        case .failed:
            return "\(providerName) could not finish this session."
        case .interrupted:
            return "This \(providerName) session was interrupted."
        case .unknown:
            return "The current state of this \(providerName) session is unknown."
        }
    }
}

private struct AgentUsageMeter: View {
    let usageWindow: AgentUsageWindow
    var showsRemaining = false

    private var clampedUsagePercentage: Double {
        min(max(usageWindow.usedPercentage, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(usageWindow.windowLabel)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(showsRemaining ? 100 - clampedUsagePercentage : usageWindow.usedPercentage,
                     format: .number.precision(.fractionLength(0)))
                    + Text(showsRemaining ? "% left" : "% used")
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)

            ProgressView(value: showsRemaining ? 100 - clampedUsagePercentage : clampedUsagePercentage, total: 100)
                .progressViewStyle(.linear)
                .tint(meterColor)

            Text(resetLabel)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(AgentActivityColor.secondaryText)
                .lineLimit(1)
        }
        .frame(width: showsRemaining ? 150 : 108)
        .help(usageWindow.windowLabel)
    }

    private var meterColor: Color {
        if usageWindow.usedPercentage >= 90 {
            return AgentActivityColor.failed
        }
        if usageWindow.usedPercentage >= 70 {
            return AgentActivityColor.attention
        }
        return AgentActivityColor.running
    }

    private var resetLabel: String {
        guard let resetDate = usageWindow.resetsAt else {
            return "Reset unavailable"
        }
        return "Resets \(resetDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct CodexAccountUsageView: View {
    @ObservedObject private var agentActivityRuntime = AgentActivityRuntime.shared
    @State private var targetQuotaWindowIndex: Int? = 0

    private var selectedQuotaWindowIndex: Int {
        targetQuotaWindowIndex ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex account usage (shared)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                if let accountUsage = agentActivityRuntime.codexAccountUsage {
                    Text("Updated \(accountUsage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(AgentActivityColor.secondaryText)
                }
            }
            if let accountUsage = agentActivityRuntime.codexAccountUsage, !accountUsage.usageWindows.isEmpty {
                HStack(spacing: 6) {
                    AgentUsageNavigationButton(direction: .previous) {
                        targetQuotaWindowIndex = selectedQuotaWindowIndex - 1
                    }
                    .disabled(selectedQuotaWindowIndex == 0)

                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(accountUsage.usageWindows.enumerated()), id: \.offset) { windowIndex, usageWindow in
                                AgentUsageMeter(usageWindow: usageWindow, showsRemaining: true)
                                    .id(windowIndex)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.visible)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollPosition(id: $targetQuotaWindowIndex, anchor: .center)

                    AgentUsageNavigationButton(direction: .next) {
                        targetQuotaWindowIndex = selectedQuotaWindowIndex + 1
                    }
                    .disabled(selectedQuotaWindowIndex >= accountUsage.usageWindows.count - 1)
                }
                .onChange(of: accountUsage.usageWindows.map(\.windowLabel)) {
                    targetQuotaWindowIndex = 0
                }
            } else {
                Text(agentActivityRuntime.codexUsageAvailability == .loading
                     ? "Reading account usage from Codex…"
                     : "Account quota unavailable from Codex CLI.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentActivityColor.secondaryText)
            }
        }
    }
}

private struct AgentUsageNavigationButton: View {
    enum Direction {
        case previous
        case next

        var label: String {
            self == .previous ? "Previous quota window" : "Next quota window"
        }

        var systemImage: String {
            self == .previous ? "chevron.left" : "chevron.right"
        }
    }

    let direction: Direction
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : AgentActivityColor.secondaryText)
                .frame(width: 24, height: 34)
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(hasKeyboardFocus ? Color.white : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($hasKeyboardFocus)
        .accessibilityLabel(direction.label)
        .help(direction.label)
        .onKeyPress(keys: [.space, .return]) { _ in
            guard isEnabled else { return .ignored }
            action()
            return .handled
        }
    }
}

private struct AgentActivityMessageView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AgentActivityColor.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AgentActivityColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AgentActivityUnavailableView: View {
    let retry: () -> Void

    @FocusState private var retryHasKeyboardFocus: Bool

    var body: some View {
        VStack(spacing: 7) {
            Label("Agent monitor unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AgentActivityColor.failed)
            Text("The local agent bridge could not start.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AgentActivityColor.secondaryText)
            Button("Retry", action: retry)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            retryHasKeyboardFocus ? Color.black : .clear,
                            lineWidth: 2
                        )
                }
                .focusable()
                .focused($retryHasKeyboardFocus)
        }
    }
}
