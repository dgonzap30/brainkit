import Foundation
import Security

public protocol UniversalAccessClock: Sendable {
    func now() -> Date
}

public protocol UniversalNonceGenerating: Sendable {
    func nonce() throws -> Data
}

public struct SystemUniversalAccessClock: UniversalAccessClock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct SystemUniversalNonceGenerator: UniversalNonceGenerating {
    public init() {}

    public func nonce() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw UniversalAccessError.credentialUnavailable
        }
        return Data(bytes)
    }
}

public final class UniversalAccessClient: @unchecked Sendable {
    private static let jsonContentType = "application/json"
    private static let standardRequestLimit = 256 * 1024
    private static let responseLimit = UniversalAccessLimits.maxCaptureHTTPBytes

    private let identityStore: any DeviceIdentityStoring
    private let session: URLSession
    private let clock: any UniversalAccessClock
    private let nonceGenerator: any UniversalNonceGenerating
    private let originOverride: URL?
    private let pinningDelegate: UniversalTLSPinningDelegate?

    public init(identityStore: any DeviceIdentityStoring) throws {
        let identity = try identityStore.load()
        let delegate = identity.map {
            UniversalTLSPinningDelegate(expectedSPKISHA256: $0.metadata.tlsSPKISHA256)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        self.identityStore = identityStore
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        clock = SystemUniversalAccessClock()
        nonceGenerator = SystemUniversalNonceGenerator()
        originOverride = nil
        pinningDelegate = delegate
    }

    init(
        identityStore: any DeviceIdentityStoring,
        session: URLSession,
        clock: any UniversalAccessClock,
        nonceGenerator: any UniversalNonceGenerating,
        originOverride: URL?
    ) {
        self.identityStore = identityStore
        self.session = session
        self.clock = clock
        self.nonceGenerator = nonceGenerator
        self.originOverride = originOverride
        pinningDelegate = nil
    }

    public static func pair(
        pairingCode: String,
        label: String,
        profile: DeviceProfileV1,
        requestId: String,
        identityStore: any DeviceIdentityStoring
    ) async throws -> PairingReceiptV1 {
        let challenge = try PairingCodeDecoder.challenge(from: pairingCode)
        let delegate = UniversalTLSPinningDelegate(
            expectedSPKISHA256: challenge.serverIdentity.tlsFingerprint
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return try await pair(
            challenge: challenge,
            label: label,
            profile: profile,
            requestId: requestId,
            identityStore: identityStore,
            session: session,
            pinningDelegate: delegate
        )
    }

    static func pair(
        pairingCode: String,
        label: String,
        profile: DeviceProfileV1,
        requestId: String,
        identityStore: any DeviceIdentityStoring,
        session: URLSession
    ) async throws -> PairingReceiptV1 {
        try await pair(
            challenge: PairingCodeDecoder.challenge(from: pairingCode),
            label: label,
            profile: profile,
            requestId: requestId,
            identityStore: identityStore,
            session: session,
            pinningDelegate: nil
        )
    }

    private static func pair(
        challenge: PairingChallengeV1,
        label: String,
        profile: DeviceProfileV1,
        requestId: String,
        identityStore: any DeviceIdentityStoring,
        session: URLSession,
        pinningDelegate: UniversalTLSPinningDelegate?
    ) async throws -> PairingReceiptV1 {
        guard challenge.scopeProfile == profile,
              challenge.clientClass.rawValue == profile.rawValue
        else {
            throw UniversalAccessError.invalidRequest
        }

        let pending: PendingDeviceIdentityV1
        do {
            pending = try identityStore.create(label: label, profile: profile)
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let publicKey = pending.publicKeyX963.base64EncodedString()
        let proof = [
            "lodestar-pairing-proof-v1",
            challenge.challengeId,
            publicKey,
        ].joined(separator: "\n")
        let signature: String
        do {
            signature = try pending.signer.signDER(Data(proof.utf8)).base64EncodedString()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        let request = PairingCompleteRequestV1(
            requestId: requestId,
            pairingCode: challenge.pairingCode,
            label: label,
            publicKeyX963: publicKey,
            proofSignature: signature
        )
        let receipt = try await completePairing(
            request,
            using: challenge,
            session: session,
            pinningDelegate: pinningDelegate
        )

        do {
            try receipt.validate()
            _ = try DeviceIdentityV1(receipt: receipt, pending: pending)
        } catch {
            throw UniversalAccessError.decoding
        }
        do {
            try identityStore.savePairing(receipt, pending: pending)
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        return receipt
    }

    public static func completePairing(
        _ request: PairingCompleteRequestV1,
        using challenge: PairingChallengeV1
    ) async throws -> PairingReceiptV1 {
        let delegate = UniversalTLSPinningDelegate(
            expectedSPKISHA256: challenge.serverIdentity.tlsFingerprint
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return try await completePairing(
            request,
            using: challenge,
            session: session,
            pinningDelegate: delegate
        )
    }

    static func completePairing(
        _ request: PairingCompleteRequestV1,
        using challenge: PairingChallengeV1,
        session: URLSession
    ) async throws -> PairingReceiptV1 {
        try await completePairing(
            request,
            using: challenge,
            session: session,
            pinningDelegate: nil
        )
    }

    private static func completePairing(
        _ request: PairingCompleteRequestV1,
        using challenge: PairingChallengeV1,
        session: URLSession,
        pinningDelegate: UniversalTLSPinningDelegate?
    ) async throws -> PairingReceiptV1 {
        do {
            try request.validate()
            try challenge.validate()
        } catch {
            throw UniversalAccessError.invalidRequest
        }
        guard request.pairingCode == challenge.pairingCode,
              let origin = URL(string: challenge.serverIdentity.origin)
        else {
            throw UniversalAccessError.invalidRequest
        }
        let url = try makeURL(origin: origin, path: "/v2/pairing/complete", queryItems: [])
        let body: Data
        do {
            body = try UniversalAccessJSON.encoder.encode(request)
        } catch {
            throw UniversalAccessError.invalidRequest
        }
        guard body.count <= standardRequestLimit else { throw UniversalAccessError.bodyTooLarge }

        var lastError: UniversalAccessError = .transport
        for attempt in 0 ..< 2 {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.httpBody = body
                urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                urlRequest.setValue(jsonContentType, forHTTPHeaderField: "Accept")
                urlRequest.setValue(jsonContentType, forHTTPHeaderField: "Content-Type")
                let (data, rawResponse) = try await session.data(for: urlRequest)
                guard let response = rawResponse as? HTTPURLResponse else {
                    throw UniversalAccessError.transport
                }
                guard data.count <= responseLimit else { throw UniversalAccessError.responseTooLarge }
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw mapServerError(
                        data: data,
                        status: response.statusCode,
                        fallbackRequestId: request.requestId
                    )
                }
                let receipt: PairingReceiptV1
                do {
                    receipt = try UniversalAccessJSON.decoder.decode(PairingReceiptV1.self, from: data)
                } catch {
                    throw UniversalAccessError.decoding
                }
                guard receipt.serverIdentity == challenge.serverIdentity,
                      receipt.clientClass == challenge.clientClass,
                      receipt.scopeProfile == challenge.scopeProfile
                else {
                    throw UniversalAccessError.decoding
                }
                return receipt
            } catch let error as UniversalAccessError {
                lastError = error
            } catch {
                lastError = pinningDelegate?.consumePinFailure() == true ? .tlsPinMismatch : .transport
            }
            if attempt == 1 || !lastError.isRetryable { throw lastError }
        }
        throw lastError
    }

    public func createPairingChallenge(_ request: PairingChallengeRequestV1) async throws -> PairingChallengeV1 {
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/devices/pairing-challenges",
            requestId: Self.readRequestID(),
            request: request,
            response: PairingChallengeV1.self
        )
    }

    public func bootstrap() async throws -> BootstrapResponseV1 {
        try await sendRead(path: "/v2/universal/bootstrap", response: BootstrapResponseV1.self)
    }

    public func uploadCapture(_ upload: CaptureUploadV1) async throws -> CaptureReceiptV1 {
        try upload.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/universal/captures",
            requestId: "request:capture-\(upload.envelope.envelopeId.uuidString.lowercased())",
            request: upload,
            contentType: UniversalAccessLimits.captureMediaType,
            requestLimit: UniversalAccessLimits.maxCaptureHTTPBytes,
            response: CaptureReceiptV1.self
        )
    }

    public func captureReceipt(envelopeId: UUID) async throws -> CaptureReceiptV1 {
        try await sendRead(
            path: "/v2/universal/captures/\(envelopeId.uuidString.lowercased())/receipt",
            response: CaptureReceiptV1.self
        )
    }

    public func conversations(cursor: String? = nil) async throws -> CursorPageV1<ConversationThreadV1> {
        try Self.validateCursor(cursor)
        return try await sendRead(
            path: "/v2/universal/conversations",
            queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
            response: CursorPageV1<ConversationThreadV1>.self
        )
    }

    public func conversationItems(
        conversationId: String,
        cursor: String? = nil
    ) async throws -> CursorPageV1<ConversationItemV1> {
        try Self.validateStableID(conversationId)
        try Self.validateCursor(cursor)
        return try await sendRead(
            path: "/v2/universal/conversations/\(try Self.pathSegment(conversationId))/items",
            queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
            response: CursorPageV1<ConversationItemV1>.self
        )
    }

    public func recall(_ request: RecallRequestV1) async throws -> RecallResponseV1 {
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/universal/recall",
            requestId: request.requestId,
            request: request,
            response: RecallResponseV1.self
        )
    }

    public func evidence(
        accessGrant: String,
        representation: EvidenceRepresentation = .content
    ) async throws -> EvidenceResponseV1 {
        guard (16 ... 512).contains(accessGrant.count) else { throw UniversalAccessError.invalidRequest }
        return try await sendRead(
            path: "/v2/universal/evidence/\(try Self.pathSegment(accessGrant))",
            queryItems: [URLQueryItem(name: "representation", value: representation.rawValue)],
            response: EvidenceResponseV1.self
        )
    }

    public func pulse() async throws -> PulseSnapshotV1 {
        try await sendRead(path: "/v2/universal/pulse", response: PulseSnapshotV1.self)
    }

    public func proposeClaims(_ request: ClaimCandidateRequestV1) async throws -> ClaimCandidateReceiptV1 {
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/universal/claim-candidates",
            requestId: request.requestId,
            request: request,
            response: ClaimCandidateReceiptV1.self
        )
    }

    public func claimExceptions(cursor: String? = nil) async throws -> CursorPageV1<ClaimExceptionV1> {
        try Self.validateCursor(cursor)
        return try await sendRead(
            path: "/v2/universal/claim-exceptions",
            queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
            response: CursorPageV1<ClaimExceptionV1>.self
        )
    }

    public func decideClaim(_ request: ClaimDecisionRequestV1) async throws -> ClaimDecisionV1 {
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/universal/claim-decisions",
            requestId: request.requestId,
            request: request,
            response: ClaimDecisionV1.self
        )
    }

    public func rotateSelf(_ request: KeyRotationRequestV1) async throws -> KeyRotationReceiptV1 {
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/devices/self/rotate",
            requestId: request.requestId,
            request: request,
            response: KeyRotationReceiptV1.self
        )
    }

    public func rotateSelf(requestId: String) async throws -> KeyRotationReceiptV1 {
        let current: DeviceIdentityV1
        do {
            guard let loaded = try identityStore.load() else {
                throw UniversalAccessError.notPaired
            }
            try loaded.metadata.validate()
            current = loaded
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let pending: PendingDeviceIdentityV1
        do {
            pending = try identityStore.create(
                label: current.metadata.label,
                profile: current.metadata.profile
            )
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        guard pending.publicKeyX963 != current.signer.publicKeyX963 else {
            throw UniversalAccessError.credentialUnavailable
        }

        let publicKey = pending.publicKeyX963.base64EncodedString()
        let proof = [
            "lodestar-key-rotation-proof-v1",
            current.metadata.deviceId,
            String(current.metadata.keyVersion),
            publicKey,
            requestId,
        ].joined(separator: "\n")
        let signature: String
        do {
            signature = try pending.signer.signDER(Data(proof.utf8)).base64EncodedString()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        let request = KeyRotationRequestV1(
            requestId: requestId,
            expectedKeyVersion: current.metadata.keyVersion,
            newPublicKeyX963: publicKey,
            newKeyProofSignature: signature
        )
        let receipt = try await rotateSelf(request)

        do {
            try receipt.validate()
            guard receipt.requestId == requestId,
                  receipt.deviceId == current.metadata.deviceId,
                  receipt.keyVersion == current.metadata.keyVersion + 1
            else {
                throw UniversalAccessError.decoding
            }
            _ = try DeviceIdentityV1(
                rotationReceipt: receipt,
                current: current,
                pending: pending
            )
        } catch {
            throw UniversalAccessError.decoding
        }
        do {
            try identityStore.saveRotation(receipt, pending: pending)
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        return receipt
    }

    public func devices() async throws -> DeviceListResponseV1 {
        try await sendRead(path: "/v2/devices", response: DeviceListResponseV1.self)
    }

    public func revokeDevice(
        deviceId: String,
        request: DeviceRevocationRequestV1
    ) async throws -> DeviceRevocationReceiptV1 {
        try Self.validateStableID(deviceId)
        try request.validate()
        return try await sendBody(
            method: "POST",
            path: "/v2/devices/\(try Self.pathSegment(deviceId))/revoke",
            requestId: request.requestId,
            request: request,
            response: DeviceRevocationReceiptV1.self
        )
    }

    private func sendRead<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        response: Response.Type
    ) async throws -> Response {
        try await send(
            method: "GET",
            path: path,
            queryItems: queryItems,
            requestId: Self.readRequestID(),
            body: Data(),
            contentType: nil,
            response: response
        )
    }

    private func sendBody<Request: Encodable, Response: Decodable>(
        method: String,
        path: String,
        requestId: String,
        request: Request,
        contentType: String = UniversalAccessClient.jsonContentType,
        requestLimit: Int = UniversalAccessClient.standardRequestLimit,
        response: Response.Type
    ) async throws -> Response {
        let body: Data
        do {
            body = try UniversalAccessJSON.encoder.encode(request)
        } catch {
            throw UniversalAccessError.invalidRequest
        }
        guard body.count <= requestLimit else { throw UniversalAccessError.bodyTooLarge }
        return try await send(
            method: method,
            path: path,
            requestId: requestId,
            body: body,
            contentType: contentType,
            response: response
        )
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        requestId: String,
        body: Data,
        contentType: String?,
        response: Response.Type
    ) async throws -> Response {
        let identity: DeviceIdentityV1
        do {
            guard let loaded = try identityStore.load() else { throw UniversalAccessError.notPaired }
            try loaded.metadata.validate()
            identity = loaded
        } catch let error as UniversalAccessError {
            throw error
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let origin = try resolvedOrigin(for: identity)
        let url = try Self.makeURL(origin: origin, path: path, queryItems: queryItems)
        var lastError: UniversalAccessError = .transport

        for attempt in 0 ..< 2 {
            do {
                let signed = try UniversalRequestSigner(signer: identity.signer).sign(
                    method: method,
                    url: url,
                    body: body,
                    timestamp: clock.now(),
                    requestId: requestId,
                    nonce: nonceGenerator.nonce()
                )
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body.isEmpty && method == "GET" ? nil : body
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.setValue(Self.jsonContentType, forHTTPHeaderField: "Accept")
                if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
                request.setValue(identity.metadata.deviceId, forHTTPHeaderField: "X-Lodestar-Device-Id")
                for (name, value) in signed.headers { request.setValue(value, forHTTPHeaderField: name) }

                let (data, rawResponse) = try await session.data(for: request)
                guard let httpResponse = rawResponse as? HTTPURLResponse else {
                    throw UniversalAccessError.transport
                }
                guard data.count <= Self.responseLimit else {
                    throw UniversalAccessError.responseTooLarge
                }
                if (200 ..< 300).contains(httpResponse.statusCode) {
                    do {
                        return try UniversalAccessJSON.decoder.decode(response, from: data)
                    } catch {
                        throw UniversalAccessError.decoding
                    }
                }
                throw Self.mapServerError(data: data, status: httpResponse.statusCode, fallbackRequestId: requestId)
            } catch let error as UniversalAccessError {
                lastError = error
            } catch {
                lastError = pinningDelegate?.consumePinFailure() == true ? .tlsPinMismatch : .transport
            }

            if attempt == 1 || !lastError.isRetryable { throw lastError }
        }
        throw lastError
    }

    private func resolvedOrigin(for identity: DeviceIdentityV1) throws -> URL {
        let paired = identity.metadata.serverOrigin
        guard let pairedKey = Self.originKey(paired) else { throw UniversalAccessError.credentialUnavailable }
        if let originOverride {
            guard Self.originKey(originOverride) == pairedKey else { throw UniversalAccessError.originMismatch }
            return originOverride
        }
        return paired
    }

    private static func mapServerError(
        data: Data,
        status: Int,
        fallbackRequestId: String
    ) -> UniversalAccessError {
        guard let envelope = try? UniversalAccessJSON.decoder.decode(UniversalAccessErrorEnvelopeV1.self, from: data) else {
            return .server(category: .unavailable, status: status, requestId: fallbackRequestId, retryable: status >= 500)
        }
        let requestId = envelope.requestId ?? fallbackRequestId
        switch envelope.category {
        case .revoked:
            return .revoked(requestId: requestId)
        case .unauthenticated:
            return .unauthenticated(requestId: requestId)
        case .rateLimited:
            return .rateLimited(requestId: requestId)
        default:
            return .server(
                category: envelope.category,
                status: status,
                requestId: requestId,
                retryable: envelope.retryable
            )
        }
    }

    private static func makeURL(origin: URL, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard path.hasPrefix("/"),
              let key = originKey(origin),
              !key.isEmpty,
              var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        else {
            throw UniversalAccessError.invalidRequest
        }
        components.percentEncodedPath = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw UniversalAccessError.invalidRequest }
        return url
    }

    private static func originKey(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return nil
        }
        return "https://\(host):\(components.port ?? 443)"
    }

    private static func pathSegment(_ value: String) throws -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw UniversalAccessError.invalidRequest
        }
        return encoded
    }

    private static func validateStableID(_ value: String) throws {
        guard value.range(of: "^[a-z][a-z0-9-]{1,47}:[a-z0-9][a-z0-9._:-]{0,159}$", options: .regularExpression) != nil else {
            throw UniversalAccessError.invalidRequest
        }
    }

    private static func validateCursor(_ cursor: String?) throws {
        if let cursor, !(1 ... 2_048).contains(cursor.count) { throw UniversalAccessError.invalidRequest }
    }

    private static func readRequestID() -> String {
        "request:\(UUID().uuidString.lowercased())"
    }
}

private enum PairingCodeDecoder {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let challengeByteCount = 16
    private static let fingerprintByteCount = 32
    private static let secretByteCount = 16

    static func challenge(from code: String) throws -> PairingChallengeV1 {
        do {
            let normalized = try normalize(code)
            let bytes = try decodeBase32(normalized)
            guard encodeBase32(bytes) == normalized else {
                throw PairingCodeError.invalid
            }

            var cursor = Cursor(bytes)
            guard try cursor.byte() == 1 else { throw PairingCodeError.invalid }
            let challengeBytes = try cursor.data(count: challengeByteCount)
            let profileByte = try cursor.byte()
            let profile: UniversalScopeProfile
            let clientClass: UniversalClientClass
            switch profileByte {
            case 0:
                profile = .reach
                clientClass = .reach
            case 1:
                profile = .lodestar
                clientClass = .lodestar
            default:
                throw PairingCodeError.invalid
            }
            let expirySeconds = try cursor.uint32()
            let origin = try cursor.text()
            let serverId = try cursor.text()
            let displayName = try cursor.text()
            let fingerprint = try cursor.data(count: fingerprintByteCount)
            _ = try cursor.data(count: secretByteCount)
            guard cursor.isAtEnd else { throw PairingCodeError.invalid }

            let challenge = PairingChallengeV1(
                schemaVersion: .pairingChallengeV1,
                challengeId: "pairing-challenge:\(hex(challengeBytes))",
                pairingCode: code,
                clientClass: clientClass,
                serverIdentity: ServerIdentityV1(
                    serverId: serverId,
                    displayName: displayName,
                    origin: origin,
                    tlsFingerprint: "sha256:\(hex(fingerprint))"
                ),
                scopeProfile: profile,
                expiresAt: timestamp(secondsSince1970: expirySeconds)
            )
            try challenge.validate()
            return challenge
        } catch {
            throw UniversalAccessError.invalidRequest
        }
    }

    private static func normalize(_ code: String) throws -> String {
        var normalized = ""
        for character in code.uppercased() {
            if character == "-" || character.isWhitespace { continue }
            switch character {
            case "O": normalized.append("0")
            case "I", "L": normalized.append("1")
            default: normalized.append(character)
            }
        }
        guard !normalized.isEmpty, normalized.count <= 256 else {
            throw PairingCodeError.invalid
        }
        return normalized
    }

    private static func decodeBase32(_ value: String) throws -> Data {
        var bytes: [UInt8] = []
        var buffer = 0
        var bitCount = 0
        for character in value {
            guard let decoded = alphabet.firstIndex(of: character) else {
                throw PairingCodeError.invalid
            }
            buffer = (buffer << 5) | decoded
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((buffer >> bitCount) & 0xff))
                buffer &= bitCount == 0 ? 0 : (1 << bitCount) - 1
            }
        }
        guard bitCount == 0 || buffer == 0 else { throw PairingCodeError.invalid }
        return Data(bytes)
    }

    private static func encodeBase32(_ bytes: Data) -> String {
        var output = ""
        var buffer = 0
        var bitCount = 0
        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[(buffer >> bitCount) & 31])
                buffer &= bitCount == 0 ? 0 : (1 << bitCount) - 1
            }
        }
        if bitCount > 0 {
            output.append(alphabet[(buffer << (5 - bitCount)) & 31])
        }
        return output
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(secondsSince1970: UInt32) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(secondsSince1970)))
    }

    private enum PairingCodeError: Error {
        case invalid
    }

    private struct Cursor {
        private let bytes: Data
        private(set) var offset = 0

        init(_ bytes: Data) {
            self.bytes = bytes
        }

        var isAtEnd: Bool { offset == bytes.count }

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw PairingCodeError.invalid }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func data(count: Int) throws -> Data {
            guard count >= 0, offset <= bytes.count - count else {
                throw PairingCodeError.invalid
            }
            let result = bytes.subdata(in: offset ..< offset + count)
            offset += count
            return result
        }

        mutating func uint32() throws -> UInt32 {
            let value = try data(count: 4)
            return value.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }

        mutating func text() throws -> String {
            let length = Int(try byte())
            guard length > 0,
                  let value = String(data: try data(count: length), encoding: .utf8)
            else {
                throw PairingCodeError.invalid
            }
            return value
        }
    }
}

final class UniversalTLSPinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let verifier: UniversalTLSPinVerifier
    private let lock = NSLock()
    private var pinFailed = false

    init(expectedSPKISHA256: String) {
        verifier = UniversalTLSPinVerifier(expectedSPKISHA256: expectedSPKISHA256)
    }

    func consumePinFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let failed = pinFailed
        pinFailed = false
        return failed
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let key = SecTrustCopyKey(trust),
              let spki = SubjectPublicKeyInfo.der(for: key)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        do {
            try verifier.validate(spkiDER: spki)
            completionHandler(.useCredential, URLCredential(trust: trust))
        } catch {
            lock.lock()
            pinFailed = true
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private enum SubjectPublicKeyInfo {
    static func der(for key: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(key, &error) as Data?,
              let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attributes[kSecAttrKeyType as String] as? String
        else {
            return nil
        }

        if type == (kSecAttrKeyTypeECSECPrimeRandom as String), raw.count == 65 {
            let algorithm = Data([
                0x30, 0x13,
                0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
                0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            ])
            return sequence(algorithm + bitString(raw))
        }
        if type == (kSecAttrKeyTypeRSA as String) {
            let algorithm = Data([
                0x30, 0x0d,
                0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
                0x05, 0x00,
            ])
            return sequence(algorithm + bitString(raw))
        }
        return nil
    }

    private static func sequence(_ contents: Data) -> Data {
        Data([0x30]) + length(contents.count) + contents
    }

    private static func bitString(_ contents: Data) -> Data {
        let body = Data([0x00]) + contents
        return Data([0x03]) + length(body.count) + body
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
