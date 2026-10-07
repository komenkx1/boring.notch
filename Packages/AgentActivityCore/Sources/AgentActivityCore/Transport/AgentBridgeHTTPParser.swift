import Foundation

enum AgentBridgeHTTPParseResult: Equatable {
    case incomplete
    case request(AgentBridgeRequest)
    case rejected(statusCode: Int)
}

enum AgentBridgeHTTPParser {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(
        _ requestBytes: Data,
        maximumHeaderLength: Int,
        maximumBodyLength: Int
    ) -> AgentBridgeHTTPParseResult {
        guard let headerRange = requestBytes.range(of: headerTerminator) else {
            return requestBytes.count > maximumHeaderLength
                ? .rejected(statusCode: 431)
                : .incomplete
        }

        let headerLength = headerRange.lowerBound
        guard headerLength <= maximumHeaderLength else {
            return .rejected(statusCode: 431)
        }
        guard let headerText = String(
            data: requestBytes[..<headerRange.lowerBound],
            encoding: .utf8
        ) else {
            return .rejected(statusCode: 400)
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            return .rejected(statusCode: 400)
        }
        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count == 3,
              requestLineParts[2].hasPrefix("HTTP/1.") else {
            return .rejected(statusCode: 400)
        }

        var headers: [String: String] = [:]
        for headerLine in headerLines.dropFirst() {
            guard let separatorIndex = headerLine.firstIndex(of: ":") else {
                return .rejected(statusCode: 400)
            }
            let headerName = headerLine[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let headerValue = headerLine[headerLine.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerName.isEmpty,
                  headers[headerName] == nil else {
                return .rejected(statusCode: 400)
            }
            headers[headerName] = headerValue
        }

        guard headers["transfer-encoding"] == nil else {
            return .rejected(statusCode: 400)
        }
        let requestMethod = String(requestLineParts[0]).uppercased()
        let contentLength: Int
        if let contentLengthText = headers["content-length"] {
            guard let parsedContentLength = Int(contentLengthText),
                  parsedContentLength >= 0 else {
                return .rejected(statusCode: 411)
            }
            contentLength = parsedContentLength
        } else if requestMethod == "GET" {
            contentLength = 0
        } else {
            return .rejected(statusCode: 411)
        }
        guard contentLength <= maximumBodyLength else {
            return .rejected(statusCode: 413)
        }

        let bodyStartIndex = headerRange.upperBound
        let availableBodyLength = requestBytes.distance(
            from: bodyStartIndex,
            to: requestBytes.endIndex
        )
        guard availableBodyLength >= contentLength else {
            return .incomplete
        }

        let bodyEndIndex = requestBytes.index(bodyStartIndex, offsetBy: contentLength)
        let requestBody = Data(requestBytes[bodyStartIndex..<bodyEndIndex])
        return .request(
            AgentBridgeRequest(
                method: String(requestLineParts[0]),
                path: String(requestLineParts[1]),
                headers: headers,
                body: requestBody
            )
        )
    }
}
