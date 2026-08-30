import CoreFoundation
import CryptoKit
import Foundation

public protocol UniversalAccessRootObject {
    static var allowedRootKeys: Set<String> { get }
}

public protocol UniversalAccessValidatable {
    func validate() throws
}

public enum UniversalAccessContractError: Error, Equatable, Sendable {
    case expectedJSONObject
    case unknownFields([String])
    case invalidField(String)
    case invariant(String)
    case unsupportedCanonicalValue
}

public struct UniversalAccessDecoder: Sendable {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let rootType = T.self as? UniversalAccessRootObject.Type {
            let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let object = raw as? [String: Any] else {
                throw UniversalAccessContractError.expectedJSONObject
            }
            let unknown = Set(object.keys).subtracting(rootType.allowedRootKeys).sorted()
            if !unknown.isEmpty {
                throw UniversalAccessContractError.unknownFields(unknown)
            }
        }

        let value = try JSONDecoder().decode(type, from: data)
        if let validatable = value as? UniversalAccessValidatable {
            try validatable.validate()
        }
        return value
    }
}

public struct UniversalAccessEncoder: Sendable {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

public enum UniversalAccessJSON {
    public static let decoder = UniversalAccessDecoder()
    public static let encoder = UniversalAccessEncoder()
}

public enum CanonicalJSON {
    public static func data<T: Encodable>(from value: T) throws -> Data {
        let encoded = try UniversalAccessJSON.encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
        return try data(fromJSONObject: object)
    }

    public static func data(fromJSONObject object: Any) throws -> Data {
        try validate(object)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    public static func string<T: Encodable>(from value: T) throws -> String {
        guard let string = String(data: try data(from: value), encoding: .utf8) else {
            throw UniversalAccessContractError.unsupportedCanonicalValue
        }
        return string
    }

    public static func sha256<T: Encodable>(of value: T) throws -> String {
        sha256(ofCanonicalData: try data(from: value))
    }

    public static func sha256(ofJSONObject object: Any) throws -> String {
        sha256(ofCanonicalData: try data(fromJSONObject: object))
    }

    public static func sha256(ofCanonicalData data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validate(_ value: Any) throws {
        switch value {
        case is NSNull, is String:
            return
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return
            }
            guard CFGetTypeID(number) == CFNumberGetTypeID(), number.doubleValue.isFinite else {
                throw UniversalAccessContractError.unsupportedCanonicalValue
            }
        case let array as [Any]:
            for item in array {
                try validate(item)
            }
        case let object as [String: Any]:
            for (key, item) in object {
                guard key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                    throw UniversalAccessContractError.unsupportedCanonicalValue
                }
                try validate(item)
            }
        default:
            throw UniversalAccessContractError.unsupportedCanonicalValue
        }
    }
}
