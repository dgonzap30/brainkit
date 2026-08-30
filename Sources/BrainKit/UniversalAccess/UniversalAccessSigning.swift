import CryptoKit
import Foundation

public protocol UniversalAccessSigner: Sendable {
    var publicKeyX963: Data { get }
    func signDER(_ data: Data) throws -> Data
}

protocol StoredUniversalAccessSigner: UniversalAccessSigner {
    var storageKind: String { get }
    func protectedStorageRepresentation() throws -> Data
}

public final class P256SoftwareUniversalAccessSigner: UniversalAccessSigner, @unchecked Sendable {
    private let privateKey: P256.Signing.PrivateKey

    public init(rawPrivateKey: Data) throws {
        privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    }

    init() {
        privateKey = P256.Signing.PrivateKey()
    }

    public var publicKeyX963: Data { privateKey.publicKey.x963Representation }

    public func signDER(_ data: Data) throws -> Data {
        try privateKey.signature(for: data).derRepresentation
    }
}

extension P256SoftwareUniversalAccessSigner: StoredUniversalAccessSigner {
    var storageKind: String { "p256-software-v1" }
    func protectedStorageRepresentation() throws -> Data { privateKey.rawRepresentation }
}

public final class SecureEnclaveUniversalAccessSigner: UniversalAccessSigner, @unchecked Sendable {
    private let privateKey: SecureEnclave.P256.Signing.PrivateKey

    init() throws {
        privateKey = try SecureEnclave.P256.Signing.PrivateKey()
    }

    init(protectedRepresentation: Data) throws {
        privateKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: protectedRepresentation)
    }

    public var publicKeyX963: Data { privateKey.publicKey.x963Representation }

    public func signDER(_ data: Data) throws -> Data {
        try privateKey.signature(for: data).derRepresentation
    }
}

extension SecureEnclaveUniversalAccessSigner: StoredUniversalAccessSigner {
    var storageKind: String { "p256-secure-enclave-v1" }
    func protectedStorageRepresentation() throws -> Data { privateKey.dataRepresentation }
}

public struct UniversalSignedRequestV1: Equatable, Sendable {
    public let canonicalString: String
    public let headers: [String: String]
}

public struct UniversalRequestSigner: Sendable {
    public static let signedHeaderNames = [
        "X-Lodestar-Device-Id",
        "X-Lodestar-Request-Id",
        "X-Lodestar-Timestamp",
        "X-Lodestar-Nonce",
        "X-Lodestar-Body-SHA256",
        "X-Lodestar-Signature",
    ]

    private let signer: any UniversalAccessSigner

    public init(signer: any UniversalAccessSigner) {
        self.signer = signer
    }

    public func sign(
        method: String,
        url: URL,
        body: Data,
        timestamp: Date,
        requestId: String,
        nonce: Data
    ) throws -> UniversalSignedRequestV1 {
        guard nonce.count == 16,
              requestId.range(of: "^[a-z][a-z0-9-]{1,47}:[a-z0-9][a-z0-9._:-]{0,159}$", options: .regularExpression) != nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil
        else {
            throw UniversalAccessError.invalidRequest
        }

        let normalizedMethod = method.uppercased()
        guard normalizedMethod.range(of: "^[A-Z]{3,12}$", options: .regularExpression) != nil else {
            throw UniversalAccessError.invalidRequest
        }

        let bodyHash = "sha256:\(CanonicalJSON.sha256(ofCanonicalData: body))"
        let timestampText = Self.timestampString(timestamp)
        let nonceText = nonce.map { String(format: "%02x", $0) }.joined()
        let pathAndQuery = try Self.normalizedPathAndQuery(components)
        let canonicalString = [
            "lodestar-signature-v1",
            normalizedMethod,
            pathAndQuery,
            bodyHash,
            timestampText,
            requestId,
            nonceText,
        ].joined(separator: "\n")
        let signature = try signer.signDER(Data(canonicalString.utf8)).base64EncodedString()

        return UniversalSignedRequestV1(
            canonicalString: canonicalString,
            headers: [
                "X-Lodestar-Request-Id": requestId,
                "X-Lodestar-Timestamp": timestampText,
                "X-Lodestar-Nonce": nonceText,
                "X-Lodestar-Body-SHA256": bodyHash,
                "X-Lodestar-Signature": signature,
            ]
        )
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter.string(from: date)
    }

    private static func normalizedPathAndQuery(_ components: URLComponents) throws -> String {
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard let queryItems = components.queryItems, !queryItems.isEmpty else { return path }

        let encoded = try queryItems.map { item -> (String, String?) in
            let name = try percentEncode(item.name)
            let value = try item.value.map(percentEncode)
            return (name, value)
        }.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return ($0.1 ?? "") < ($1.1 ?? "")
        }
        let query = encoded.map { name, value in
            value.map { "\(name)=\($0)" } ?? name
        }.joined(separator: "&")
        return "\(path)?\(query)"
    }

    private static func percentEncode(_ value: String) throws -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw UniversalAccessError.invalidRequest
        }
        return encoded
    }
}

public struct UniversalTLSPinVerifier: Sendable {
    public let expectedSPKISHA256: String

    public init(expectedSPKISHA256: String) {
        self.expectedSPKISHA256 = expectedSPKISHA256
    }

    public func validate(spkiDER: Data) throws {
        let actual = "sha256:\(CanonicalJSON.sha256(ofCanonicalData: spkiDER))"
        guard Self.constantTimeEqual(actual, expectedSPKISHA256) else {
            throw UniversalAccessError.tlsPinMismatch
        }
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}
