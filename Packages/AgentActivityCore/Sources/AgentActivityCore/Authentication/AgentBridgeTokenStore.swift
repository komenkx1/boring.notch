import Foundation
import Security

public enum AgentBridgeTokenStoreError: Error, Equatable, Sendable {
    case unexpectedKeychainValue
    case keychainFailure(OSStatus)
    case randomGenerationFailure(OSStatus)
}

public struct AgentBridgeTokenStore: Sendable {
    private let serviceName: String
    private let accountName: String

    public init(
        serviceName: String = "theboringteam.boringnotch.agent-bridge",
        accountName: String = "local-http-bearer-token"
    ) {
        self.serviceName = serviceName
        self.accountName = accountName
    }

    public func loadOrCreateToken() throws -> String {
        if let storedToken = try loadToken() {
            return storedToken
        }

        let generatedToken = try generateToken()
        let tokenBytes = Data(generatedToken.utf8)
        let addTokenQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: tokenBytes
        ]
        let keychainStatus = SecItemAdd(addTokenQuery as CFDictionary, nil)

        if keychainStatus == errSecDuplicateItem,
           let concurrentlyCreatedToken = try loadToken() {
            return concurrentlyCreatedToken
        }
        guard keychainStatus == errSecSuccess else {
            throw AgentBridgeTokenStoreError.keychainFailure(keychainStatus)
        }
        return generatedToken
    }

    private func loadToken() throws -> String? {
        let findTokenQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keychainValue: CFTypeRef?
        let keychainStatus = SecItemCopyMatching(
            findTokenQuery as CFDictionary,
            &keychainValue
        )

        if keychainStatus == errSecItemNotFound {
            return nil
        }
        guard keychainStatus == errSecSuccess else {
            throw AgentBridgeTokenStoreError.keychainFailure(keychainStatus)
        }
        guard let tokenBytes = keychainValue as? Data,
              let storedToken = String(data: tokenBytes, encoding: .utf8) else {
            throw AgentBridgeTokenStoreError.unexpectedKeychainValue
        }
        return storedToken
    }

    private func generateToken() throws -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )
        guard randomStatus == errSecSuccess else {
            throw AgentBridgeTokenStoreError.randomGenerationFailure(randomStatus)
        }

        return Data(randomBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
