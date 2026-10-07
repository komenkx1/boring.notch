import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let booleanValue = try? container.decode(Bool.self) {
            self = .boolean(booleanValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let stringValue):
            try container.encode(stringValue)
        case .number(let numberValue):
            try container.encode(numberValue)
        case .boolean(let booleanValue):
            try container.encode(booleanValue)
        case .object(let objectValue):
            try container.encode(objectValue)
        case .array(let arrayValue):
            try container.encode(arrayValue)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        guard case .string(let stringValue) = self else {
            return nil
        }
        return stringValue
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let objectValue) = self else {
            return nil
        }
        return objectValue[key]
    }
}
