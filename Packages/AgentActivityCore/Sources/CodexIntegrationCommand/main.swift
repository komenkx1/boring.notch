import AgentActivityCore
import Foundation

@main
enum CodexIntegrationCommand {
    static func main() async {
        let command = CommandLine.arguments.dropFirst().first ?? "help"
        do {
            let settingsManager = CodexIntegrationSettingsManager()
            switch command {
            case "preview":
                print(String(decoding: try settingsManager.preview(), as: UTF8.self))
            case "install":
                let bearerToken = try ProcessInfo.processInfo.environment[AgentBridgeConfiguration.claudeTokenEnvironmentName]
                    ?? AgentBridgeTokenStore().loadOrCreateToken()
                try settingsManager.install(executableBytes: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0])))
                try Data(bearerToken.utf8).write(to: settingsManager.tokenFile, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsManager.tokenFile.path)
                print("Codex monitoring installed. Review and trust the Boring Notch hooks with /hooks in Codex.")
            case "uninstall":
                try settingsManager.uninstall()
                print("Boring Notch Codex hooks removed. Existing hooks and the backup were preserved.")
            case "forward-hook":
                await forwardHook()
                print("{}")
            default:
                print("Usage: boring-notch-codex-integration <preview|install|uninstall|forward-hook>")
            }
        } catch {
            if command == "forward-hook" { print("{}"); return }
            FileHandle.standardError.write(Data("Codex integration failed: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func forwardHook() async {
        guard let hookBody = try? FileHandle.standardInput.readToEnd(), hookBody.count <= 65_536,
              let bearerToken = try? String(contentsOf: CodexIntegrationSettingsManager().tokenFile, encoding: .utf8),
              !bearerToken.isEmpty else { return }
        var hookRequest = URLRequest(url: AgentBridgeConfiguration.codexHookEndpoint)
        hookRequest.httpMethod = "POST"
        hookRequest.httpBody = hookBody
        hookRequest.timeoutInterval = 1
        hookRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        hookRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: hookRequest)
    }
}
