import Foundation

public enum AgentBridgeConfiguration {
    public static let loopbackHost = "127.0.0.1"
    public static let listeningPort: UInt16 = 48_763
    public static let claudeTokenEnvironmentName = "BORING_NOTCH_AGENT_TOKEN"
    public static let keychainServiceName = "theboringteam.boringnotch.agent-bridge"
    public static let keychainAccountName = "local-http-bearer-token"

    public static var claudeHookEndpoint: URL {
        URL(string: "http://\(loopbackHost):\(listeningPort)/v1/hooks/claude")!
    }

    public static var claudeStatusEndpoint: URL {
        URL(string: "http://\(loopbackHost):\(listeningPort)/v1/status/claude")!
    }
}
