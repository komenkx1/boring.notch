import Foundation
import Network

public enum LocalAgentHTTPReceiverError: Error, Equatable, Sendable {
    case alreadyRunning
    case invalidPort(UInt16)
    case listenerStoppedBeforeReady
    case missingListeningPort
}

public final class LocalAgentHTTPReceiver: @unchecked Sendable {
    private let requestProcessor: AgentBridgeRequestProcessor
    private let listenerQueue: DispatchQueue
    private let stateLock = NSLock()
    private var listener: NWListener?

    public init(
        requestProcessor: AgentBridgeRequestProcessor,
        listenerQueue: DispatchQueue = DispatchQueue(label: "agent-activity.local-http")
    ) {
        self.requestProcessor = requestProcessor
        self.listenerQueue = listenerQueue
    }

    deinit {
        stop()
    }

    public func start(port requestedPort: UInt16 = 0) async throws -> UInt16 {
        let networkPort: NWEndpoint.Port
        if requestedPort == 0 {
            networkPort = .any
        } else if let specifiedPort = NWEndpoint.Port(rawValue: requestedPort) {
            networkPort = specifiedPort
        } else {
            throw LocalAgentHTTPReceiverError.invalidPort(requestedPort)
        }

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: networkPort
        )
        let newListener = try NWListener(using: parameters)
        try install(newListener)

        return try await withCheckedThrowingContinuation { continuation in
            let continuationGate = ReceiverStartupContinuation(continuation: continuation)

            newListener.stateUpdateHandler = { [weak self] listenerState in
                switch listenerState {
                case .ready:
                    guard let listeningPort = newListener.port else {
                        continuationGate.resume(
                            throwing: LocalAgentHTTPReceiverError.missingListeningPort
                        )
                        self?.stop()
                        return
                    }
                    continuationGate.resume(returning: listeningPort.rawValue)
                case .failed(let networkError):
                    continuationGate.resume(throwing: networkError)
                    self?.clearListener(ifMatching: newListener)
                case .cancelled:
                    continuationGate.resume(
                        throwing: LocalAgentHTTPReceiverError.listenerStoppedBeforeReady
                    )
                    self?.clearListener(ifMatching: newListener)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            newListener.start(queue: listenerQueue)
        }
    }

    public func stop() {
        stateLock.lock()
        let activeListener = listener
        listener = nil
        stateLock.unlock()
        activeListener?.cancel()
    }

    private func install(_ newListener: NWListener) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listener == nil else {
            throw LocalAgentHTTPReceiverError.alreadyRunning
        }
        listener = newListener
    }

    private func clearListener(ifMatching finishedListener: NWListener) {
        stateLock.lock()
        if listener === finishedListener {
            listener = nil
        }
        stateLock.unlock()
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] connectionState in
            guard let self, let connection else {
                return
            }
            switch connectionState {
            case .ready:
                self.receiveRequest(from: connection, accumulatedBytes: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: listenerQueue)
    }

    private func receiveRequest(
        from connection: NWConnection,
        accumulatedBytes: Data
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self, weak connection] receivedBytes, _, isComplete, receiveError in
            guard let self, let connection else {
                return
            }

            var requestBytes = accumulatedBytes
            if let receivedBytes {
                requestBytes.append(receivedBytes)
            }

            switch AgentBridgeHTTPParser.parse(
                requestBytes,
                maximumHeaderLength: 16_384,
                maximumBodyLength: self.requestProcessor.maximumRequestBodyLength
            ) {
            case .request(let bridgeRequest):
                Task {
                    let bridgeResponse = await self.requestProcessor.process(bridgeRequest)
                    self.send(bridgeResponse, over: connection)
                }
            case .rejected(let statusCode):
                self.send(AgentBridgeResponse(statusCode: statusCode), over: connection)
            case .incomplete:
                if isComplete || receiveError != nil {
                    self.send(AgentBridgeResponse(statusCode: 400), over: connection)
                } else {
                    self.receiveRequest(from: connection, accumulatedBytes: requestBytes)
                }
            }
        }
    }

    private func send(_ response: AgentBridgeResponse, over connection: NWConnection) {
        let reasonPhrase = HTTPReasonPhrase.text(for: response.statusCode)
        let responseHead = "HTTP/1.1 \(response.statusCode) \(reasonPhrase)\r\n"
            + "Content-Length: \(response.body.count)\r\n"
            + (response.contentType.map { "Content-Type: \($0)\r\n" } ?? "")
            + "Connection: close\r\n"
            + "\r\n"
        var responseBytes = Data(responseHead.utf8)
        responseBytes.append(response.body)
        connection.send(
            content: responseBytes,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}

private final class ReceiverStartupContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning listeningPort: UInt16) {
        takeContinuation()?.resume(returning: listeningPort)
    }

    func resume(throwing startupError: Error) {
        takeContinuation()?.resume(throwing: startupError)
    }

    private func takeContinuation() -> CheckedContinuation<UInt16, Error>? {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        lock.unlock()
        return pendingContinuation
    }
}

private enum HTTPReasonPhrase {
    static func text(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        default: "Error"
        }
    }
}
