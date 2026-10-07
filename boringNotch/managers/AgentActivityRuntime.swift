import AgentActivityCore
import Foundation

@MainActor
final class AgentActivityRuntime {
    static let shared = AgentActivityRuntime()

    let activityStore = AgentActivityStore()

    private var localReceiver: LocalAgentHTTPReceiver?
    private var startupTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard startupTask == nil, localReceiver == nil else {
            return
        }

        startupTask = Task { @MainActor in
            do {
                let bearerToken = try AgentBridgeTokenStore().loadOrCreateToken()
                try Task.checkCancellation()
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
                NSLog("Claude agent bridge listening on 127.0.0.1:%d", listeningPort)
            } catch is CancellationError {
                localReceiver?.stop()
                localReceiver = nil
            } catch {
                localReceiver?.stop()
                localReceiver = nil
                NSLog("Claude agent bridge could not start: %@", String(describing: error))
            }
            startupTask = nil
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        localReceiver?.stop()
        localReceiver = nil
    }
}
