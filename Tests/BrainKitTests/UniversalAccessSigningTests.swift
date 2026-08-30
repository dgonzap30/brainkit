import XCTest
import CryptoKit
@testable import BrainKit

final class UniversalAccessSigningTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_777_777_777.123)
    private let requestID = "request:signing-0001"
    private let nonce = Data((0 ..< 16).map(UInt8.init))

    func testCanonicalStringNormalizesMethodQueryBodyTimestampRequestAndNonce() throws {
        let signer = try softwareSigner()
        let requestSigner = UniversalRequestSigner(signer: signer)
        let url = try XCTUnwrap(URL(string: "https://mini.example/v2/universal/recall?b=two%20words&a=1&a=%2Fslash"))
        let body = Data("{\"query\":\"blue notebook\"}".utf8)

        let signed = try requestSigner.sign(
            method: "post",
            url: url,
            body: body,
            timestamp: timestamp,
            requestId: requestID,
            nonce: nonce
        )

        let expectedBodyHash = "sha256:\(CanonicalJSON.sha256(ofCanonicalData: body))"
        XCTAssertEqual(
            signed.canonicalString,
            """
            lodestar-signature-v1
            POST
            /v2/universal/recall?a=%2Fslash&a=1&b=two%20words
            \(expectedBodyHash)
            2026-05-03T03:09:37.123Z
            request:signing-0001
            000102030405060708090a0b0c0d0e0f
            """
        )
        XCTAssertEqual(signed.headers["X-Lodestar-Device-Id"], nil)
        XCTAssertEqual(signed.headers["X-Lodestar-Request-Id"], requestID)
        XCTAssertEqual(signed.headers["X-Lodestar-Body-SHA256"], expectedBodyHash)
        XCTAssertEqual(signed.headers["X-Lodestar-Nonce"], "000102030405060708090a0b0c0d0e0f")
    }

    func testReorderedQueryProducesSameCanonicalStringAndEmptyBodyHashIsFrozen() throws {
        let signer = UniversalRequestSigner(signer: try softwareSigner())
        let left = try signer.sign(
            method: "GET",
            url: XCTUnwrap(URL(string: "https://mini.example/v2/devices?z=last&a=first")),
            body: Data(),
            timestamp: timestamp,
            requestId: requestID,
            nonce: nonce
        )
        let right = try signer.sign(
            method: "GET",
            url: XCTUnwrap(URL(string: "https://mini.example/v2/devices?a=first&z=last")),
            body: Data(),
            timestamp: timestamp,
            requestId: requestID,
            nonce: nonce
        )
        XCTAssertEqual(left.canonicalString, right.canonicalString)
        XCTAssertEqual(
            left.headers["X-Lodestar-Body-SHA256"],
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testSignatureIsPaddedBase64DERAndVerifiesAgainstX963PublicKey() throws {
        let software = try softwareSigner()
        let signed = try UniversalRequestSigner(signer: software).sign(
            method: "POST",
            url: XCTUnwrap(URL(string: "https://mini.example/v2/universal/recall")),
            body: Data("{}".utf8),
            timestamp: timestamp,
            requestId: requestID,
            nonce: nonce
        )
        let signatureData = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(signed.headers["X-Lodestar-Signature"])))
        XCTAssertEqual(signatureData.base64EncodedString(), signed.headers["X-Lodestar-Signature"])
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        let publicKey = try P256.Signing.PublicKey(x963Representation: software.publicKeyX963)
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(signed.canonicalString.utf8)))
    }

    func testNonceMustBeExactlySixteenBytes() throws {
        XCTAssertThrowsError(try UniversalRequestSigner(signer: softwareSigner()).sign(
            method: "GET",
            url: XCTUnwrap(URL(string: "https://mini.example/v2/devices")),
            body: Data(),
            timestamp: timestamp,
            requestId: requestID,
            nonce: Data(repeating: 0, count: 15)
        ))
    }

    func testTLSPinVerifierRejectsMismatch() throws {
        let expectedBytes = Data("expected-spki".utf8)
        let expected = "sha256:\(CanonicalJSON.sha256(ofCanonicalData: expectedBytes))"
        let verifier = UniversalTLSPinVerifier(expectedSPKISHA256: expected)
        XCTAssertNoThrow(try verifier.validate(spkiDER: expectedBytes))
        XCTAssertThrowsError(try verifier.validate(spkiDER: Data("different-spki".utf8))) { error in
            XCTAssertEqual(error as? UniversalAccessError, .tlsPinMismatch)
        }
    }

    func testDeviceMetadataEncodingContainsNoPrivateKeyOrReusableSecret() throws {
        let metadata = DeviceIdentityMetadataV1(
            serverOrigin: try XCTUnwrap(URL(string: "https://mini.example")),
            serverIdentity: "server:mini",
            tlsSPKISHA256: "sha256:\(String(repeating: "a", count: 64))",
            deviceId: "device:test",
            label: "Diego iPhone",
            profile: .reach,
            scopes: reachUniversalAccessScopes,
            domains: [.inbox, .personal],
            keyVersion: 1
        )
        let encoded = try JSONEncoder().encode(metadata)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("private"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("signature"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(text.contains(Data(repeating: 1, count: 32).base64EncodedString()))
    }

    private func softwareSigner() throws -> P256SoftwareUniversalAccessSigner {
        var raw = Data(repeating: 0, count: 32)
        raw[31] = 1
        return try P256SoftwareUniversalAccessSigner(rawPrivateKey: raw)
    }
}
