import Darwin
import Foundation

public enum CodexAccountUsageError: Error, Equatable {
    case executableUnavailable
    case requestFailed
    case invalidResponse
    case responseTooLarge
    case timedOut
    case serverExited
}

public struct CodexAccountUsageReader: Sendable {
    private let executableURL: URL?
    private let timeout: TimeInterval

    public init(executableURL: URL? = nil, timeout: TimeInterval = 15) {
        self.executableURL = executableURL
        self.timeout = max(1, min(timeout, 30))
    }

    public func readUsage() async throws -> CodexAccountUsage {
        let executableURL = try self.executableURL ?? Self.findExecutable()
        let timeout = self.timeout
        return try await Task.detached(priority: .utility) {
            try CodexUsageRequestSession(executableURL: executableURL, timeout: timeout).readUsage()
        }.value
    }

    private static func findExecutable() throws -> URL {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = pathDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            + [URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex"),
               FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex")]
        guard let executableURL = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CodexAccountUsageError.executableUnavailable
        }
        return executableURL
    }
}

private final class CodexUsageRequestSession: @unchecked Sendable {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let completionSignal = DispatchSemaphore(value: 0)
    private let responseLock = NSLock()
    private let timeout: TimeInterval
    private var pendingOutput = Data()
    private var receivedByteCount = 0
    private var initializationAcknowledged = false
    private var usageOutcome: Result<CodexAccountUsage, Error>?

    init(executableURL: URL, timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio", "-c", "analytics.enabled=false"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
    }

    func readUsage() throws -> CodexAccountUsage {
        var didLaunch = false
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] outputHandle in
            let outputBytes = outputHandle.availableData
            if outputBytes.isEmpty { self?.finish(.failure(CodexAccountUsageError.serverExited)) }
            else { self?.consume(outputBytes) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.finish(.failure(CodexAccountUsageError.serverExited))
        }
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? inputPipe.fileHandleForWriting.close()
            if didLaunch {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
        }
        try process.run()
        didLaunch = true
        try? outputPipe.fileHandleForWriting.close()
        try? inputPipe.fileHandleForReading.close()
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": [
            "name": "boring_notch_usage", "title": "Boring Notch Usage", "version": "0.1.0"]]])
        if completionSignal.wait(timeout: .now() + timeout) == .timedOut {
            finish(.failure(CodexAccountUsageError.timedOut))
        }
        responseLock.lock()
        let completedOutcome = usageOutcome
        responseLock.unlock()
        return try (completedOutcome ?? .failure(CodexAccountUsageError.serverExited)).get()
    }

    private func consume(_ outputBytes: Data) {
        responseLock.lock()
        defer { responseLock.unlock() }
        guard usageOutcome == nil else { return }
        receivedByteCount += outputBytes.count
        guard receivedByteCount <= 524_288 else {
            completeLocked(.failure(CodexAccountUsageError.responseTooLarge))
            return
        }
        pendingOutput.append(outputBytes)
        while let newlineIndex = pendingOutput.firstIndex(of: 10), usageOutcome == nil {
            let responseLine = Data(pendingOutput[..<newlineIndex])
            pendingOutput.removeSubrange(...newlineIndex)
            do {
                guard let response = try JSONSerialization.jsonObject(with: responseLine) as? [String: Any],
                      let requestIdentifier = response["id"] as? Int else { continue }
                guard requestIdentifier == 1 || requestIdentifier == 2 else { continue }
                guard response["error"] == nil, let responseResult = response["result"] else {
                    completeLocked(.failure(CodexAccountUsageError.requestFailed))
                    return
                }
                if requestIdentifier == 1, !initializationAcknowledged {
                    initializationAcknowledged = true
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if requestIdentifier == 2, initializationAcknowledged {
                    let responseBody = try JSONSerialization.data(withJSONObject: responseResult)
                    completeLocked(.success(try CodexRateLimitsDecoder().decodeResponse(from: responseBody)))
                }
            } catch {
                completeLocked(.failure(CodexAccountUsageError.invalidResponse))
            }
        }
    }

    private func send(_ request: [String: Any]) throws {
        var requestBytes = try JSONSerialization.data(withJSONObject: request, options: [.withoutEscapingSlashes, .sortedKeys])
        requestBytes.append(10)
        try inputPipe.fileHandleForWriting.write(contentsOf: requestBytes)
    }

    private func finish(_ outcome: Result<CodexAccountUsage, Error>) {
        responseLock.lock()
        defer { responseLock.unlock() }
        completeLocked(outcome)
    }

    private func completeLocked(_ outcome: Result<CodexAccountUsage, Error>) {
        guard usageOutcome == nil else { return }
        usageOutcome = outcome
        completionSignal.signal()
    }
}
