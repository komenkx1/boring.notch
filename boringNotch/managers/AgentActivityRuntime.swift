import AgentActivityCore
import AppKit
import Combine
import Foundation

enum AgentBridgeAvailability: Equatable {
    case starting
    case listening
    case unavailable
}

enum CodexUsageAvailability: Equatable {
    case notInstalled
    case loading
    case available
    case unavailable
}

@MainActor
final class AgentActivityRuntime: ObservableObject {
    static let shared = AgentActivityRuntime()

    let activityStore = AgentActivityStore()
    @Published private(set) var agentRuns: [AgentRun] = []
    @Published private(set) var claudePermissionRequests: [ClaudePermissionRequest] = []
    @Published private(set) var bridgeAvailability: AgentBridgeAvailability = .starting
    @Published private(set) var codexAccountUsage: CodexAccountUsage?
    @Published private(set) var codexUsageAvailability: CodexUsageAvailability = .notInstalled

    private var localReceiver: LocalAgentHTTPReceiver?
    private var startupTask: Task<Void, Never>?
    private var activityRefreshTask: Task<Void, Never>?
    private var usageRefreshTask: Task<Void, Never>?
    private var permissionStore: ClaudePermissionStore?

    private init() {}

    func start() {
        guard startupTask == nil, localReceiver == nil else {
            return
        }

        bridgeAvailability = .starting
        startupTask = Task { @MainActor in
            do {
                let installedTokenFile = CodexIntegrationSettingsManager().tokenFile
                let installedCodexToken = try? String(contentsOf: installedTokenFile, encoding: .utf8)
                let bearerToken = try installedCodexToken.flatMap { $0.isEmpty ? nil : $0 }
                    ?? AgentBridgeTokenStore().loadOrCreateToken()
                try Task.checkCancellation()
                await activityStore.removeAll()
                let permissionStore = ClaudePermissionStore(activityStore: activityStore)
                self.permissionStore = permissionStore
                let requestProcessor = AgentBridgeRequestProcessor(
                    tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(
                        expectedBearerToken: bearerToken
                    ),
                    activityStore: activityStore,
                    permissionStore: permissionStore
                )
                let receiver = LocalAgentHTTPReceiver(requestProcessor: requestProcessor)
                localReceiver = receiver
                let listeningPort = try await receiver.start(
                    port: AgentBridgeConfiguration.listeningPort
                )
                bridgeAvailability = .listening
                startRefreshingAgentRuns()
                startRefreshingCodexUsage()
                NSLog("Agent bridge listening on 127.0.0.1:%d", listeningPort)
            } catch is CancellationError {
                localReceiver?.stop()
                localReceiver = nil
            } catch {
                localReceiver?.stop()
                localReceiver = nil
                bridgeAvailability = .unavailable
                NSLog("Agent bridge could not start: %@", String(describing: error))
            }
            startupTask = nil
        }
    }

    func retry() {
        stop()
        start()
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        activityRefreshTask?.cancel()
        activityRefreshTask = nil
        usageRefreshTask?.cancel()
        usageRefreshTask = nil
        codexAccountUsage = nil
        codexUsageAvailability = .notInstalled
        localReceiver?.stop()
        localReceiver = nil
        bridgeAvailability = .unavailable
        agentRuns = []
        claudePermissionRequests = []
        if let permissionStore {
            Task { await permissionStore.removeAll() }
        }
        permissionStore = nil
    }

    func decideClaudePermission(_ decision: ClaudePermissionDecision, requestIdentifier: UUID) async -> Bool {
        guard bridgeAvailability == .listening, let permissionStore,
              let notchWindow = NSApp.windows.compactMap({ $0 as? BoringNotchSkyLightWindow })
                .first(where: { $0.isVisible && $0.canBecomeKey }) else { return false }
        notchWindow.makeKey()
        let accepted = await permissionStore.decide(decision, requestIdentifier: requestIdentifier)
        claudePermissionRequests = await permissionStore.requests()
        return accepted
    }

    func answerClaudeQuestions(_ answers: [String: String], requestIdentifier: UUID) async -> Bool {
        guard bridgeAvailability == .listening, let permissionStore,
              let notchWindow = NSApp.windows.compactMap({ $0 as? BoringNotchSkyLightWindow })
                .first(where: { $0.isVisible && $0.canBecomeKey }) else { return false }
        notchWindow.makeKey()
        let accepted = await permissionStore.answerQuestions(answers, requestIdentifier: requestIdentifier)
        claudePermissionRequests = await permissionStore.requests()
        return accepted
    }

    func returnQuestionsToClaude(requestIdentifier: UUID) async -> Bool {
        guard bridgeAvailability == .listening, let permissionStore else { return false }
        let accepted = await permissionStore.returnQuestionsToClaude(requestIdentifier: requestIdentifier)
        claudePermissionRequests = await permissionStore.requests()
        return accepted
    }

    private func startRefreshingAgentRuns() {
        activityRefreshTask?.cancel()
        activityRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await activityStore.reconcileActivityFreshness()
                let latestAgentRuns = await activityStore.agentRuns()
                if agentRuns != latestAgentRuns {
                    agentRuns = latestAgentRuns
                }
                let latestPermissionRequests = await permissionStore?.requests() ?? []
                if claudePermissionRequests != latestPermissionRequests {
                    claudePermissionRequests = latestPermissionRequests
                }

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
        }
    }

    private func startRefreshingCodexUsage() {
        guard FileManager.default.fileExists(atPath: CodexIntegrationSettingsManager().tokenFile.path) else { return }
        usageRefreshTask?.cancel()
        usageRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                codexUsageAvailability = .loading
                do {
                    let latestAccountUsage = try await CodexAccountUsageReader().readUsage()
                    try Task.checkCancellation()
                    codexAccountUsage = latestAccountUsage
                    codexUsageAvailability = latestAccountUsage.usageWindows.isEmpty ? .unavailable : .available
                } catch {
                    guard !Task.isCancelled else { return }
                    codexAccountUsage = nil
                    codexUsageAvailability = .unavailable
                }
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
            }
        }
    }
}
