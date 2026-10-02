import Foundation

/// A value from a collector's JSON record. The collectors and the panel agree
/// on field names, not on types, so values stay loose until they're read, and
/// they're read the way the GNOME panel's JavaScript reads them.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self {
            return fields[key]
        }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let fields) = self {
            return fields
        }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self {
            return items
        }
        return nil
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// Literals, for sample records in the tests and the panel snapshots.
extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// JavaScript's coercions, for the few places the panel relies on them.
enum JS {
    /// `!!value`
    static func truthy(_ value: JSONValue?) -> Bool {
        switch value {
        case nil, .null?: return false
        case .bool(let flag)?: return flag
        case .number(let n)?: return n != 0 && !n.isNaN
        case .string(let text)?: return !text.isEmpty
        case .array?, .object?: return true
        }
    }

    /// `Number(value)`
    static func number(_ value: JSONValue?) -> Double {
        switch value {
        case nil: return .nan
        case .null?: return 0
        case .bool(let flag)?: return flag ? 1 : 0
        case .number(let n)?: return n
        case .string(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return 0
            }
            return Double(trimmed) ?? .nan
        case .array?, .object?: return .nan
        }
    }

    /// `String(value || '')`
    static func text(_ value: JSONValue?) -> String {
        guard truthy(value) else {
            return ""
        }
        switch value {
        case .string(let text)?: return text
        case .bool(let flag)?: return flag ? "true" : "false"
        case .number(let n)?:
            if n == n.rounded(), abs(n) < 1e15 {
                return String(Int64(n))
            }
            return String(n)
        default: return ""
        }
    }

    /// `Math.round(value)`: halves round up, toward +∞.
    static func round(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }
}
