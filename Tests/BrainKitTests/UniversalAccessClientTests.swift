import XCTest
import CryptoKit
@testable import BrainKit

private final class UniversalAccessMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest, Int) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            captured.httpBody = Self.readAll(stream)
        }
        let index = Self.requests.count
        Self.requests.append(captured)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (response, data) = handler(captured, index)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class TestDeviceIdentityStore: DeviceIdentityStoring, @unchecked Sendable {
    var identity: DeviceIdentityV1?
    var pendingSigners: [any UniversalAccessSigner]
    var savePairingCount = 0
    var saveRotationCount = 0
    init(identity: DeviceIdentityV1?, pendingSigners: [any UniversalAccessSigner] = []) {
        self.identity = identity
        self.pendingSigners = pendingSigners
    }
    func load() throws -> DeviceIdentityV1? { identity }
    func create(label: String, profile: DeviceProfileV1) throws -> PendingDeviceIdentityV1 {
        let signer = pendingSigners.isEmpty ? try testSoftwareSigner() : pendingSigners.removeFirst()
        return try PendingDeviceIdentityV1(label: label, profile: profile, signer: signer)
    }
    func savePairing(_ receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws {
        savePairingCount += 1
        identity = try DeviceIdentityV1(receipt: receipt, pending: pending)
    }
    func saveRotation(_ receipt: KeyRotationReceiptV1, pending: PendingDeviceIdentityV1) throws {
        saveRotationCount += 1
        guard let current = identity else { throw UniversalAccessError.notPaired }
        identity = try DeviceIdentityV1(rotationReceipt: receipt, current: current, pending: pending)
    }
    func removeOperationalCredential() throws { identity = nil }
}

private final class SequenceClock: UniversalAccessClock, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]
    init(_ values: [Date]) { self.values = values }
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty ? Date(timeIntervalSince1970: 0) : values.removeFirst()
    }
}

private final class SequenceNonceGenerator: UniversalNonceGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data]
    init(_ values: [Data]) { self.values = values }
    func nonce() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !values.isEmpty else { throw UniversalAccessError.invalidRequest }
        return values.removeFirst()
    }
}

final class UniversalAccessClientTests: XCTestCase {
    override func tearDown() {
        UniversalAccessMockURLProtocol.handler = nil
        UniversalAccessMockURLProtocol.requests = []
    }

    func testRecallSendsExactBodyContentTypeAndSixSignedHeaders() async throws {
        respondWithFixture("recall-response.v1", status: 200)
        let request = RecallRequestV1(
            requestId: "request:recall-0001",
            conversationId: "conversation:default",
            query: "blue notebook",
            limit: 10
        )
        let client = try makeClient()

        _ = try await client.recall(request)

        let sent = try XCTUnwrap(UniversalAccessMockURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.path, "/v2/universal/recall")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.httpBody, try UniversalAccessJSON.encoder.encode(request))
        for header in UniversalRequestSigner.signedHeaderNames {
            XCTAssertNotNil(sent.value(forHTTPHeaderField: header), "missing \(header)")
        }
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Lodestar-Device-Id"), "device:test")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Lodestar-Request-Id"), request.requestId)
    }

    func testRetryKeepsMutationRequestIDAndBodyButRefreshesTimestampNonceAndSignature() async throws {
        let retryBody = #"{"schemaVersion":"universal-access-error.v1","requestId":"request:recall-0001","category":"unavailable","message":"try again","retryable":true}"#
        let success = try fixtureData("recall-response.v1")
        UniversalAccessMockURLProtocol.handler = { request, index in
            let status = index == 0 ? 503 : 200
            let data = index == 0 ? Data(retryBody.utf8) : success
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let request = RecallRequestV1(
            requestId: "request:recall-0001",
            conversationId: "conversation:default",
            query: "blue notebook",
            limit: 10
        )

        _ = try await makeClient().recall(request)

        XCTAssertEqual(UniversalAccessMockURLProtocol.requests.count, 2)
        let first = UniversalAccessMockURLProtocol.requests[0]
        let second = UniversalAccessMockURLProtocol.requests[1]
        XCTAssertEqual(first.httpBody, second.httpBody)
        XCTAssertEqual(first.value(forHTTPHeaderField: "X-Lodestar-Request-Id"), second.value(forHTTPHeaderField: "X-Lodestar-Request-Id"))
        XCTAssertNotEqual(first.value(forHTTPHeaderField: "X-Lodestar-Timestamp"), second.value(forHTTPHeaderField: "X-Lodestar-Timestamp"))
        XCTAssertNotEqual(first.value(forHTTPHeaderField: "X-Lodestar-Nonce"), second.value(forHTTPHeaderField: "X-Lodestar-Nonce"))
        XCTAssertNotEqual(first.value(forHTTPHeaderField: "X-Lodestar-Signature"), second.value(forHTTPHeaderField: "X-Lodestar-Signature"))
    }

    func testRevokedResponseMapsWithoutLeakingServerBodyMessage() async throws {
        let canary = "capture text /Users/diego/private signature=secret"
        let body = #"{"schemaVersion":"universal-access-error.v1","requestId":"request:recall-0001","category":"revoked","message":"\#(canary)","retryable":false}"#
        respond(status: 403, data: Data(body.utf8))
        let request = RecallRequestV1(
            requestId: "request:recall-0001",
            conversationId: "conversation:default",
            query: "blue notebook",
            limit: 10
        )

        await XCTAssertThrowsErrorAsync(try await makeClient().recall(request)) { error in
            XCTAssertEqual(error as? UniversalAccessError, .revoked(requestId: request.requestId))
            XCTAssertFalse(error.localizedDescription.contains(canary))
            XCTAssertFalse(String(describing: error).contains("/Users/diego/private"))
        }
    }

    func testClientRefusesOriginOverrideThatDiffersFromPairedOrigin() async throws {
        let client = try makeClient(originOverride: URL(string: "https://attacker.example")!)
        let request = RecallRequestV1(
            requestId: "request:recall-0001",
            conversationId: "conversation:default",
            query: "blue notebook",
            limit: 10
        )
        await XCTAssertThrowsErrorAsync(try await client.recall(request)) { error in
            XCTAssertEqual(error as? UniversalAccessError, .originMismatch)
        }
        XCTAssertTrue(UniversalAccessMockURLProtocol.requests.isEmpty)
    }

    func testUnpairedClientRefusesToSend() async throws {
        let client = UniversalAccessClient(
            identityStore: TestDeviceIdentityStore(identity: nil),
            session: testSession(),
            clock: SequenceClock([Date()]),
            nonceGenerator: SequenceNonceGenerator([Data(repeating: 1, count: 16)]),
            originOverride: nil
        )
        let request = RecallRequestV1(
            requestId: "request:recall-0001",
            conversationId: "conversation:default",
            query: "blue notebook",
            limit: 10
        )
        await XCTAssertThrowsErrorAsync(try await client.recall(request)) { error in
            XCTAssertEqual(error as? UniversalAccessError, .notPaired)
        }
    }

    func testPairingCompleteUsesLearnedServerIdentityWithoutOperationalHeaders() async throws {
        respondWithFixture("pairing-receipt.v1", status: 200)
        let challenge = PairingChallengeV1(
            schemaVersion: .pairingChallengeV1,
            challengeId: "pairing-challenge:test",
            pairingCode: "ABCD-EFGH-IJKL-MNOP",
            clientClass: .reach,
            serverIdentity: ServerIdentityV1(
                serverId: "server:lodestar-mini",
                displayName: "Lodestar Mini",
                origin: "https://lodestar-mini.example.invalid:443",
                tlsFingerprint: "sha256:0e44ce7308af2b3d7d8b97bf1396e148724a95d21cb5c3bcc65dd71a3b1ec14d"
            ),
            scopeProfile: .reach,
            expiresAt: "2026-05-03T03:14:37.123Z"
        )
        let request = PairingCompleteRequestV1(
            requestId: "request:pairing-0001",
            pairingCode: challenge.pairingCode,
            label: "Diego iPhone",
            publicKeyX963: Data(repeating: 1, count: 65).base64EncodedString(),
            proofSignature: Data(repeating: 2, count: 64).base64EncodedString()
        )

        _ = try await UniversalAccessClient.completePairing(
            request,
            using: challenge,
            session: testSession()
        )

        let sent = try XCTUnwrap(UniversalAccessMockURLProtocol.requests.first)
        XCTAssertEqual(sent.url?.path, "/v2/pairing/complete")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.httpBody, try UniversalAccessJSON.encoder.encode(request))
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Lodestar-Device-Id"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Lodestar-Signature"))
    }

    func testTask11RoutesUseExactMethodsPathsAndContentTypes() async throws {
        let captureReceipt = try fixtureData("capture-receipt.v1")
        let challenge = Data(#"{"schemaVersion":"pairing-challenge.v1","challengeId":"pairing-challenge:test","pairingCode":"ABCD-EFGH-IJKL-MNOP","clientClass":"reach","serverIdentity":{"serverId":"server:mini","displayName":"Lodestar Mini","origin":"https://mini.example","tlsFingerprint":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"scopeProfile":"reach","expiresAt":"2026-08-29T22:05:00.000Z"}"#.utf8)
        let bootstrap = Data(#"{"schemaVersion":"bootstrap-response.v1","serverIdentity":{"serverId":"server:mini","displayName":"Lodestar Mini","origin":"https://mini.example","tlsFingerprint":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"deviceId":"device:test","policy":{"profile":"reach","scopes":["scope:devices.self.rotate","scope:universal.capture.write","scope:universal.claims.decide","scope:universal.claims.propose","scope:universal.claims.read","scope:universal.context.read","scope:universal.conversation.read","scope:universal.conversation.write","scope:universal.evidence.read"],"domains":["inbox","personal"],"maximumClassification":"restricted"},"defaultConversation":{"id":"conversation:default","title":"Inbox","createdAt":"2026-08-29T22:00:00.000Z","updatedAt":"2026-08-29T22:00:00.000Z"},"generatedAt":"2026-08-29T22:00:00.000Z"}"#.utf8)
        let devices = Data(#"{"schemaVersion":"device-list-response.v1","devices":[],"generatedAt":"2026-08-29T22:00:00.000Z"}"#.utf8)
        let rotation = Data(#"{"schemaVersion":"key-rotation-receipt.v1","requestId":"request:rotation-wire","deviceId":"device:test","keyVersion":2,"rotatedAt":"2026-08-29T22:00:00.000Z"}"#.utf8)
        let revocation = Data(#"{"schemaVersion":"device-revocation-receipt.v1","requestId":"request:revocation-wire","deviceId":"device:reach-target","keyVersion":1,"revokedAt":"2026-08-29T22:00:00.000Z"}"#.utf8)
        UniversalAccessMockURLProtocol.handler = { request, _ in
            let data: Data
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v2/devices/pairing-challenges"):
                data = challenge
            case ("GET", "/v2/universal/bootstrap"):
                data = bootstrap
            case ("POST", "/v2/universal/captures"),
                 ("GET", "/v2/universal/captures/11111111-1111-4111-8111-111111111111/receipt"):
                data = captureReceipt
            case ("GET", "/v2/devices"):
                data = devices
            case ("POST", "/v2/devices/self/rotate"):
                data = rotation
            case ("POST", "/v2/devices/device:reach-target/revoke"):
                data = revocation
            default:
                data = Data()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = try makeClient(requestCount: 7)
        let envelope = try UniversalAccessJSON.decoder.decode(
            CaptureEnvelopeV1.self,
            from: fixtureData("capture-envelope.v1")
        )
        let upload = CaptureUploadV1(
            envelope: envelope,
            attachmentBodies: [
                CaptureAttachmentBodyV1(
                    attachmentId: envelope.attachments[0].attachmentId,
                    contentBase64: "/9j/2Q=="
                ),
            ]
        )

        _ = try await client.createPairingChallenge(PairingChallengeRequestV1(clientClass: .reach))
        _ = try await client.bootstrap()
        _ = try await client.uploadCapture(upload)
        _ = try await client.captureReceipt(envelopeId: envelope.envelopeId)
        _ = try await client.devices()
        _ = try await client.rotateSelf(KeyRotationRequestV1(
            requestId: "request:rotation-wire",
            expectedKeyVersion: 1,
            newPublicKeyX963: Data(repeating: 1, count: 65).base64EncodedString(),
            newKeyProofSignature: Data(repeating: 2, count: 64).base64EncodedString()
        ))
        _ = try await client.revokeDevice(
            deviceId: "device:reach-target",
            request: DeviceRevocationRequestV1(
                requestId: "request:revocation-wire",
                expectedKeyVersion: 1,
                reason: "retired"
            )
        )

        XCTAssertEqual(UniversalAccessMockURLProtocol.requests.map { request in
            (request.httpMethod!, request.url!.path, request.value(forHTTPHeaderField: "Content-Type"))
        }.map { "\($0.0) \($0.1) \($0.2 ?? "nil")" }, [
            "POST /v2/devices/pairing-challenges application/json",
            "GET /v2/universal/bootstrap nil",
            "POST /v2/universal/captures application/vnd.lodestar.capture+json",
            "GET /v2/universal/captures/11111111-1111-4111-8111-111111111111/receipt nil",
            "GET /v2/devices nil",
            "POST /v2/devices/self/rotate application/json",
            "POST /v2/devices/device:reach-target/revoke application/json",
        ])
        for request in UniversalAccessMockURLProtocol.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Lodestar-Device-Id"), "device:test")
            for header in UniversalRequestSigner.signedHeaderNames {
                XCTAssertNotNil(request.value(forHTTPHeaderField: header), "missing \(header)")
            }
        }
    }

    func testEvidenceReadSendsTheExplicitRepresentationQuery() async throws {
        let response = Data(#"{"schemaVersion":"evidence-response.v1","evidence":{"id":"evidence:contract","domain":"inbox","kind":"capture.text","classification":"private","observedAt":"2026-08-29T22:30:00.000Z","contentHash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","accessGrant":"grant_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","grantExpiresAt":"2026-08-29T22:40:00.000Z"},"disposition":"metadata"}"#.utf8)
        respond(status: 200, data: response)

        _ = try await makeClient().evidence(
            accessGrant: "grant_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            representation: .metadata
        )

        let request = try XCTUnwrap(UniversalAccessMockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v2/universal/evidence/grant_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems, [
            URLQueryItem(name: "representation", value: "metadata"),
        ])
    }

    func testHighLevelPairingDecodesCodeCreatesKeySignsProofAndStoresOnlyAfterReceiptValidation() async throws {
        respondWithFixture("pairing-receipt.v1", status: 200)
        let store = TestDeviceIdentityStore(identity: nil)
        let code = "040128HK8HAPCXW8-K6NBQK6XXVZG0TFP-QPEJJT3MEHR76EHF-5XP6YS35EDT62WHD-DNMPWT9ECNW62VBG-DHJJWTBEESGPRTB4-78T38CRMEDJQ4XK5-E8X6RVV4CNSQ8RBJ-5NPPJVK91N66YS35-EDT62WH09NMPWT8E-8K77625F5CYQV2WQ-QW9SDRA8E959BMGW-PQ1VSHJXTWD3P7P1-9QZYXQECQEN9K23Q-CSAM8CS22400"

        let receipt = try await UniversalAccessClient.pair(
            pairingCode: code,
            label: "Diego iPhone",
            profile: .reach,
            requestId: "request:pairing-0001",
            identityStore: store,
            session: testSession()
        )

        XCTAssertEqual(receipt.deviceId, store.identity?.metadata.deviceId)
        XCTAssertEqual(store.savePairingCount, 1)
        let sent = try XCTUnwrap(UniversalAccessMockURLProtocol.requests.first)
        let body = try XCTUnwrap(sent.httpBody)
        let request = try UniversalAccessJSON.decoder.decode(PairingCompleteRequestV1.self, from: body)
        let publicKeyData = try XCTUnwrap(Data(base64Encoded: request.publicKeyX963))
        let signatureData = try XCTUnwrap(Data(base64Encoded: request.proofSignature))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let proof = "lodestar-pairing-proof-v1\npairing-challenge:00112233445566778899aabbccddeeff\n\(request.publicKeyX963)"
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(proof.utf8)))
        XCTAssertEqual(request.pairingCode, code)
    }

    func testHighLevelPairingDoesNotStorePendingKeyWhenReceiptBindingIsInvalid() async throws {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: fixtureData("pairing-receipt.v1")) as? [String: Any]
        )
        object["scopeProfile"] = "lodestar"
        respond(status: 200, data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        let store = TestDeviceIdentityStore(identity: nil)
        let code = "040128HK8HAPCXW8-K6NBQK6XXVZG0TFP-QPEJJT3MEHR76EHF-5XP6YS35EDT62WHD-DNMPWT9ECNW62VBG-DHJJWTBEESGPRTB4-78T38CRMEDJQ4XK5-E8X6RVV4CNSQ8RBJ-5NPPJVK91N66YS35-EDT62WH09NMPWT8E-8K77625F5CYQV2WQ-QW9SDRA8E959BMGW-PQ1VSHJXTWD3P7P1-9QZYXQECQEN9K23Q-CSAM8CS22400"

        await XCTAssertThrowsErrorAsync(try await UniversalAccessClient.pair(
            pairingCode: code,
            label: "Diego iPhone",
            profile: .reach,
            requestId: "request:pairing-0001",
            identityStore: store,
            session: testSession()
        )) { error in
            XCTAssertEqual(error as? UniversalAccessError, .decoding)
        }
        XCTAssertNil(store.identity)
        XCTAssertEqual(store.savePairingCount, 0)
    }

    func testHighLevelRotationProvesNewKeyAndPersistsItOnlyAfterBoundReceipt() async throws {
        let oldSigner = try testSoftwareSigner(scalar: 1)
        let newSigner = try testSoftwareSigner(scalar: 2)
        let current = DeviceIdentityV1(
            metadata: DeviceIdentityMetadataV1(
                serverOrigin: URL(string: "https://mini.example")!,
                serverIdentity: "server:mini",
                tlsSPKISHA256: "sha256:\(String(repeating: "a", count: 64))",
                deviceId: "device:test",
                label: "Diego iPhone",
                profile: .reach,
                scopes: reachUniversalAccessScopes,
                domains: [.inbox, .personal],
                keyVersion: 1
            ),
            signer: oldSigner
        )
        let store = TestDeviceIdentityStore(identity: current, pendingSigners: [newSigner])
        var sawOldIdentityBeforeResponse = false
        UniversalAccessMockURLProtocol.handler = { request, _ in
            sawOldIdentityBeforeResponse = store.identity?.metadata.keyVersion == 1
            let body = request.httpBody ?? Data()
            let rotation = try! UniversalAccessJSON.decoder.decode(KeyRotationRequestV1.self, from: body)
            let publicKeyData = Data(base64Encoded: rotation.newPublicKeyX963)!
            let signatureData = Data(base64Encoded: rotation.newKeyProofSignature)!
            let signature = try! P256.Signing.ECDSASignature(derRepresentation: signatureData)
            let publicKey = try! P256.Signing.PublicKey(x963Representation: publicKeyData)
            let proof = "lodestar-key-rotation-proof-v1\ndevice:test\n1\n\(rotation.newPublicKeyX963)\nrequest:rotation-0001"
            XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(proof.utf8)))
            let receipt = KeyRotationReceiptV1(
                schemaVersion: .keyRotationReceiptV1,
                requestId: "request:rotation-0001",
                deviceId: "device:test",
                keyVersion: 2,
                rotatedAt: "2026-05-03T03:09:37.123Z"
            )
            let data = try! UniversalAccessJSON.encoder.encode(receipt)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = UniversalAccessClient(
            identityStore: store,
            session: testSession(),
            clock: SequenceClock([Date(timeIntervalSince1970: 1_777_777_777.123)]),
            nonceGenerator: SequenceNonceGenerator([Data(repeating: 1, count: 16)]),
            originOverride: nil
        )

        let receipt = try await client.rotateSelf(requestId: "request:rotation-0001")

        XCTAssertTrue(sawOldIdentityBeforeResponse)
        XCTAssertEqual(receipt.keyVersion, 2)
        XCTAssertEqual(store.saveRotationCount, 1)
        XCTAssertEqual(store.identity?.metadata.keyVersion, 2)
        XCTAssertEqual(store.identity?.signer.publicKeyX963, newSigner.publicKeyX963)
    }

    func testHighLevelRotationKeepsCurrentLocalCredentialWhenReceiptDoesNotBindNextVersion() async throws {
        let oldSigner = try testSoftwareSigner(scalar: 1)
        let newSigner = try testSoftwareSigner(scalar: 2)
        let current = DeviceIdentityV1(
            metadata: DeviceIdentityMetadataV1(
                serverOrigin: URL(string: "https://mini.example")!,
                serverIdentity: "server:mini",
                tlsSPKISHA256: "sha256:\(String(repeating: "a", count: 64))",
                deviceId: "device:test",
                label: "Diego iPhone",
                profile: .reach,
                scopes: reachUniversalAccessScopes,
                domains: [.inbox, .personal],
                keyVersion: 1
            ),
            signer: oldSigner
        )
        let store = TestDeviceIdentityStore(identity: current, pendingSigners: [newSigner])
        let receipt = KeyRotationReceiptV1(
            schemaVersion: .keyRotationReceiptV1,
            requestId: "request:rotation-0001",
            deviceId: "device:test",
            keyVersion: 3,
            rotatedAt: "2026-05-03T03:09:37.123Z"
        )
        respond(status: 200, data: try UniversalAccessJSON.encoder.encode(receipt))
        let client = UniversalAccessClient(
            identityStore: store,
            session: testSession(),
            clock: SequenceClock([Date(timeIntervalSince1970: 1_777_777_777.123)]),
            nonceGenerator: SequenceNonceGenerator([Data(repeating: 1, count: 16)]),
            originOverride: nil
        )

        await XCTAssertThrowsErrorAsync(try await client.rotateSelf(requestId: "request:rotation-0001")) { error in
            XCTAssertEqual(error as? UniversalAccessError, .decoding)
        }
        XCTAssertEqual(store.saveRotationCount, 0)
        XCTAssertEqual(store.identity?.metadata.keyVersion, 1)
        XCTAssertEqual(store.identity?.signer.publicKeyX963, oldSigner.publicKeyX963)
    }

    private func makeClient(originOverride: URL? = nil, requestCount: Int = 2) throws -> UniversalAccessClient {
        let identity = DeviceIdentityV1(
            metadata: DeviceIdentityMetadataV1(
                serverOrigin: URL(string: "https://mini.example")!,
                serverIdentity: "server:mini",
                tlsSPKISHA256: "sha256:\(String(repeating: "a", count: 64))",
                deviceId: "device:test",
                label: "Diego iPhone",
                profile: .reach,
                scopes: reachUniversalAccessScopes,
                domains: [.inbox, .personal],
                keyVersion: 1
            ),
            signer: try testSoftwareSigner()
        )
        return UniversalAccessClient(
            identityStore: TestDeviceIdentityStore(identity: identity),
            session: testSession(),
            clock: SequenceClock((0 ..< max(2, requestCount)).map {
                Date(timeIntervalSince1970: 1_777_777_777.123 + Double($0))
            }),
            nonceGenerator: SequenceNonceGenerator((0 ..< max(2, requestCount)).map {
                Data(repeating: UInt8($0 + 1), count: 16)
            }),
            originOverride: originOverride
        )
    }

    private func testSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UniversalAccessMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func respondWithFixture(_ name: String, status: Int) {
        respond(status: status, data: try! fixtureData(name))
    }

    private func respond(status: Int, data: Data) {
        UniversalAccessMockURLProtocol.handler = { request, _ in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private func testSoftwareSigner() throws -> P256SoftwareUniversalAccessSigner {
    try testSoftwareSigner(scalar: 1)
}

private func testSoftwareSigner(scalar: UInt8) throws -> P256SoftwareUniversalAccessSigner {
    var raw = Data(repeating: 0, count: 32)
    raw[31] = scalar
    return try P256SoftwareUniversalAccessSigner(rawPrivateKey: raw)
}
