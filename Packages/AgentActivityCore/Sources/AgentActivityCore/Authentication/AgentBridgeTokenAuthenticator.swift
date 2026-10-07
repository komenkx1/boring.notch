import Foundation

public protocol AgentBridgeTokenAuthenticating: Sendable {
    func accepts(bearerToken: String) -> Bool
}

public struct FixedAgentBridgeTokenAuthenticator: AgentBridgeTokenAuthenticating {
    private let expectedBearerTokenBytes: [UInt8]

    public init(expectedBearerToken: String) {
        expectedBearerTokenBytes = Array(expectedBearerToken.utf8)
    }

    public func accepts(bearerToken: String) -> Bool {
        let suppliedBearerTokenBytes = Array(bearerToken.utf8)
        let comparisonLength = max(
            expectedBearerTokenBytes.count,
            suppliedBearerTokenBytes.count
        )
        var difference = expectedBearerTokenBytes.count ^ suppliedBearerTokenBytes.count

        for byteIndex in 0..<comparisonLength {
            let expectedByte = byteIndex < expectedBearerTokenBytes.count
                ? expectedBearerTokenBytes[byteIndex]
                : 0
            let suppliedByte = byteIndex < suppliedBearerTokenBytes.count
                ? suppliedBearerTokenBytes[byteIndex]
                : 0
            difference |= Int(expectedByte ^ suppliedByte)
        }

        return difference == 0
    }
}
