import XCTest
@testable import BrainKit

final class UniversalAccessContractTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testCaptureEnvelopeFixtureHasCanonicalHash() throws {
        let data = try fixtureData("capture-envelope.v1")
        let envelope = try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: data)
        XCTAssertEqual(envelope.schemaVersion, .captureEnvelopeV1)
        XCTAssertEqual(try envelope.recomputedHash(), envelope.envelopeHash)
        XCTAssertEqual(envelope.attachments.map(\.ordinal), [0])
    }

    func testEveryCanonicalFixtureDecodesAndRoundTrips() throws {
        try roundTrip(CaptureEnvelopeV1.self, fixture: "capture-envelope.v1")
        try roundTrip(CaptureReceiptV1.self, fixture: "capture-receipt.v1")
        try roundTrip(PairingReceiptV1.self, fixture: "pairing-receipt.v1")
        try roundTrip(RecallResponseV1.self, fixture: "recall-response.v1")
        try roundTrip(PulseSnapshotV1.self, fixture: "pulse-snapshot.v1")
        try roundTrip(ClaimDecisionV1.self, fixture: "claim-decision.v1")
    }

    func testFixtureRootsRejectUnknownFields() throws {
        try assertUnknownRootRejected(CaptureEnvelopeV1.self, fixture: "capture-envelope.v1")
        try assertUnknownRootRejected(CaptureReceiptV1.self, fixture: "capture-receipt.v1")
        try assertUnknownRootRejected(PairingReceiptV1.self, fixture: "pairing-receipt.v1")
        try assertUnknownRootRejected(RecallResponseV1.self, fixture: "recall-response.v1")
        try assertUnknownRootRejected(PulseSnapshotV1.self, fixture: "pulse-snapshot.v1")
        try assertUnknownRootRejected(ClaimDecisionV1.self, fixture: "claim-decision.v1")
    }

    func testCaptureAcceptsPhotoOnlyAndRejectsWhitespaceOnly() throws {
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("capture-envelope.v1")) as? [String: Any])
        fixture.removeValue(forKey: "text")
        XCTAssertNoThrow(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))

        fixture["attachments"] = []
        fixture["text"] = " \n\t "
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))
    }

    func testCaptureLimitsAndAttachmentInvariantsAreEnforced() throws {
        var fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("capture-envelope.v1")) as? [String: Any])
        fixture["text"] = String(repeating: "x", count: UniversalAccessLimits.maxCaptureTextCharacters + 1)
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))

        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("capture-envelope.v1")) as? [String: Any])
        let attachment = try XCTUnwrap((fixture["attachments"] as? [[String: Any]])?.first)
        fixture["attachments"] = (0 ... UniversalAccessLimits.maxAttachments).map { ordinal in
            var copy = attachment
            copy["ordinal"] = ordinal
            copy["attachmentId"] = String(format: "33333333-3333-4333-8333-%012d", ordinal)
            return copy
        }
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))

        fixture["attachments"] = [attachment, attachment]
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))

        var gap = attachment
        gap["ordinal"] = 1
        gap["attachmentId"] = "44444444-4444-4444-8444-444444444444"
        fixture["attachments"] = [gap]
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))

        var oversize = attachment
        oversize["byteCount"] = UniversalAccessLimits.maxAttachmentBytes + 1
        fixture["attachments"] = [oversize]
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(CaptureEnvelopeV1.self, from: jsonData(fixture)))
    }

    func testRequestBoundsAndServerOwnedFieldInjectionAreRejected() throws {
        let publicKey = Data(repeating: 1, count: 65).base64EncodedString()
        let signature = Data(repeating: 2, count: 70).base64EncodedString()
        var pairing: [String: Any] = [
            "schemaVersion": "pairing-complete-request.v1",
            "requestId": "request:pairing-0001",
            "pairingCode": "ABCD-EFGH",
            "label": "Reach",
            "publicKeyX963": publicKey,
            "proofSignature": signature,
        ]
        XCTAssertNoThrow(try UniversalAccessJSON.decoder.decode(PairingCompleteRequestV1.self, from: jsonData(pairing)))
        pairing["actorId"] = "actor:injected"
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(PairingCompleteRequestV1.self, from: jsonData(pairing)))

        pairing.removeValue(forKey: "actorId")
        pairing["label"] = String(repeating: "x", count: 81)
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(PairingCompleteRequestV1.self, from: jsonData(pairing)))

        let recall: [String: Any] = [
            "schemaVersion": "recall-request.v1",
            "requestId": "request:recall-0002",
            "conversationId": "conversation:default",
            "query": String(repeating: "q", count: 2_001),
            "limit": 10,
        ]
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(RecallRequestV1.self, from: jsonData(recall)))

        let candidate: [String: Any] = [
            "schemaVersion": "claim-candidate-request.v1",
            "requestId": "request:candidate-0001",
            "conversationId": "conversation:default",
            "evidenceHandles": ["grant_b", "grant_a"],
            "instruction": "Interpret this evidence",
        ]
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(ClaimCandidateRequestV1.self, from: jsonData(candidate)))
    }

    func testCaptureUploadRequiresExactlyOneBoundedBodyPerManifestAttachment() throws {
        let envelope = try UniversalAccessJSON.decoder.decode(
            CaptureEnvelopeV1.self,
            from: fixtureData("capture-envelope.v1")
        )
        let validBody = CaptureAttachmentBodyV1(
            attachmentId: envelope.attachments[0].attachmentId,
            contentBase64: "/9j/2Q=="
        )
        XCTAssertNoThrow(try CaptureUploadV1(envelope: envelope, attachmentBodies: [validBody]).validated())
        XCTAssertThrowsError(try CaptureUploadV1(envelope: envelope, attachmentBodies: []).validated())
        XCTAssertThrowsError(try CaptureUploadV1(envelope: envelope, attachmentBodies: [validBody, validBody]).validated())
        XCTAssertThrowsError(try CaptureUploadV1(
            envelope: envelope,
            attachmentBodies: [.init(attachmentId: UUID(), contentBase64: "/9j/2Q==")]
        ).validated())
    }

    func testCanonicalJSONRejectsNonFiniteNumbers() throws {
        XCTAssertThrowsError(try CanonicalJSON.data(from: JSONValue.number(Double.infinity)))
        XCTAssertThrowsError(try CanonicalJSON.data(from: JSONValue.number(Double.nan)))
    }

    func testEvidenceResponseRequiresOneMediaAppropriateContentBody() throws {
        let evidence = #"{"id":"evidence:contract","domain":"inbox","kind":"capture.text","classification":"private","observedAt":"2026-08-29T22:30:00.000Z","contentHash":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","accessGrant":"grant_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","grantExpiresAt":"2026-08-29T22:40:00.000Z"}"#
        let valid = Data(#"{"schemaVersion":"evidence-response.v1","evidence":\#(evidence),"disposition":"content","mediaType":"text/plain; charset=utf-8","text":"exact text"}"#.utf8)
        XCTAssertNoThrow(try UniversalAccessJSON.decoder.decode(EvidenceResponseV1.self, from: valid))

        let missingBody = Data(#"{"schemaVersion":"evidence-response.v1","evidence":\#(evidence),"disposition":"content","mediaType":"text/plain; charset=utf-8"}"#.utf8)
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(EvidenceResponseV1.self, from: missingBody))

        let wrongMedia = Data(#"{"schemaVersion":"evidence-response.v1","evidence":\#(evidence),"disposition":"content","mediaType":"image/jpeg","text":"wrong"}"#.utf8)
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(EvidenceResponseV1.self, from: wrongMedia))

        let bothBodies = Data(#"{"schemaVersion":"evidence-response.v1","evidence":\#(evidence),"disposition":"content","mediaType":"image/jpeg","text":"wrong","contentBase64":"/9j/2Q=="}"#.utf8)
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(EvidenceResponseV1.self, from: bothBodies))
    }

    func testEvidenceUnavailableErrorCategoryDecodes() throws {
        let data = Data(#"{"schemaVersion":"universal-access-error.v1","category":"evidence_unavailable","message":"Evidence is unavailable.","retryable":false}"#.utf8)
        let envelope = try UniversalAccessJSON.decoder.decode(UniversalAccessErrorEnvelopeV1.self, from: data)
        XCTAssertEqual(envelope.category, .evidenceUnavailable)
    }

    private func roundTrip<T: Codable & Equatable>(_ type: T.Type, fixture: String) throws {
        let value = try UniversalAccessJSON.decoder.decode(type, from: fixtureData(fixture))
        let encoded = try UniversalAccessJSON.encoder.encode(value)
        XCTAssertEqual(try UniversalAccessJSON.decoder.decode(type, from: encoded), value)
    }

    private func assertUnknownRootRejected<T: Decodable>(_ type: T.Type, fixture: String) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(fixture)) as? [String: Any])
        object["actorId"] = "actor:injected"
        XCTAssertThrowsError(try UniversalAccessJSON.decoder.decode(type, from: jsonData(object)))
    }
}
