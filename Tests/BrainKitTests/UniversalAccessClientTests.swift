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
    init(identity: DeviceIdentityV1?) { self.identity = identity }
    func load() throws -> DeviceIdentityV1? { identity }
    func create(label: String, profile: DeviceProfileV1) throws -> PendingDeviceIdentityV1 {
        try PendingDeviceIdentityV1(label: label, profile: profile, signer: testSoftwareSigner())
    }
    func savePairing(_ receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws {
        identity = try DeviceIdentityV1(receipt: receipt, pending: pending)
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

    private func makeClient(originOverride: URL? = nil) throws -> UniversalAccessClient {
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
            clock: SequenceClock([
                Date(timeIntervalSince1970: 1_777_777_777.123),
                Date(timeIntervalSince1970: 1_777_777_778.456),
            ]),
            nonceGenerator: SequenceNonceGenerator([
                Data(repeating: 1, count: 16),
                Data(repeating: 2, count: 16),
            ]),
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
    var raw = Data(repeating: 0, count: 32)
    raw[31] = 1
    return try P256SoftwareUniversalAccessSigner(rawPrivateKey: raw)
}
