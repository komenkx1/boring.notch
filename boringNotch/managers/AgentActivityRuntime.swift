import AgentActivityCore
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
    @Published private(set) var bridgeAvailability: AgentBridgeAvailability = .starting
    @Published private(set) var codexAccountUsage: CodexAccountUsage?
    @Published private(set) var codexUsageAvailability: CodexUsageAvailability = .notInstalled

    private var localReceiver: LocalAgentHTTPReceiver?
    private var startupTask: Task<Void, Never>?
    private var activityRefreshTask: Task<Void, Never>?
    private var usageRefreshTask: Task<Void, Never>?

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
                let requestProcessor = AgentBridgeRequestProcessor(
                    tokenAuthenticator: FixedAgentBridgeTokenAuthenticator(
                        expectedBearerToken: bearerToken
                    ),
                    activityStore: activityStore
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
