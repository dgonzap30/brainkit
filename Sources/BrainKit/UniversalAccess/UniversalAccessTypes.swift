import Foundation

public enum UniversalAccessLimits {
    public static let maxCaptureTextCharacters = 20_000
    public static let maxAttachments = 4
    public static let maxAttachmentBytes = 5 * 1024 * 1024
    public static let maxCaptureHTTPBytes = 30 * 1024 * 1024
    public static let signatureClockSkewMilliseconds = 5 * 60 * 1_000
    public static let nonceRetentionMilliseconds = 10 * 60 * 1_000
    public static let pairingChallengeTTLMilliseconds = 5 * 60 * 1_000
    public static let evidenceGrantTTLMilliseconds = 10 * 60 * 1_000
    public static let captureMediaType = "application/vnd.lodestar.capture+json"
}

public let reachUniversalAccessScopes = [
    "scope:devices.self.rotate",
    "scope:universal.capture.write",
    "scope:universal.claims.decide",
    "scope:universal.claims.propose",
    "scope:universal.claims.read",
    "scope:universal.context.read",
    "scope:universal.conversation.read",
    "scope:universal.conversation.write",
    "scope:universal.evidence.read",
]

public let lodestarUniversalAccessScopes = [
    "scope:devices.manage",
    "scope:devices.self.rotate",
    "scope:universal.claims.decide",
    "scope:universal.claims.propose",
    "scope:universal.claims.read",
    "scope:universal.context.read",
    "scope:universal.conversation.read",
    "scope:universal.conversation.write",
    "scope:universal.evidence.read",
]

public enum UniversalAccessSchemaVersion: String, Codable, Equatable, Sendable {
    case pairingChallengeRequestV1 = "pairing-challenge-request.v1"
    case pairingCompleteRequestV1 = "pairing-complete-request.v1"
    case keyRotationRequestV1 = "key-rotation-request.v1"
    case recallRequestV1 = "recall-request.v1"
    case claimCandidateRequestV1 = "claim-candidate-request.v1"
    case claimDecisionRequestV1 = "claim-decision-request.v1"
    case deviceRevocationRequestV1 = "device-revocation-request.v1"
    case captureEnvelopeV1 = "capture-envelope.v1"
    case captureReceiptV1 = "capture-receipt.v1"
    case pairingChallengeV1 = "pairing-challenge.v1"
    case pairingReceiptV1 = "pairing-receipt.v1"
    case bootstrapResponseV1 = "bootstrap-response.v1"
    case cursorPageV1 = "cursor-page.v1"
    case recallResponseV1 = "recall-response.v1"
    case evidenceResponseV1 = "evidence-response.v1"
    case pulseSnapshotV1 = "pulse-snapshot.v1"
    case claimCandidateReceiptV1 = "claim-candidate-receipt.v1"
    case claimDecisionV1 = "claim-decision.v1"
    case deviceListResponseV1 = "device-list-response.v1"
    case keyRotationReceiptV1 = "key-rotation-receipt.v1"
    case deviceRevocationReceiptV1 = "device-revocation-receipt.v1"
    case universalAccessErrorV1 = "universal-access-error.v1"
}

public enum UniversalClientClass: String, Codable, Equatable, Sendable {
    case reach
    case lodestar
}

public enum UniversalAccessDomain: String, Codable, Equatable, Sendable, Comparable {
    case inbox
    case personal

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum UniversalScopeProfile: String, Codable, Equatable, Sendable {
    case reach
    case lodestar
}

public enum CaptureSource: String, Codable, Equatable, Sendable {
    case reachApp = "reach.app"
    case reachAppIntent = "reach.app-intent"
}

public enum UniversalEvidenceClassification: String, Codable, Equatable, Sendable {
    case `private`
    case sensitive
    case restricted
}

public enum UniversalFreshness: String, Codable, Equatable, Sendable {
    case current
    case stale
    case unknown
}

public enum ConversationItemKind: String, Codable, Equatable, Sendable {
    case capture
    case recallQuery = "recall-query"
    case recallResult = "recall-result"
    case synthesisAnswer = "synthesis-answer"
    case clarification
    case claimDecision = "claim-decision"
}

public enum ClaimKind: String, Codable, Equatable, Sendable {
    case commitment
    case constraint
    case decision
    case fact
    case preference
    case procedure
    case projectState = "project_state"
    case question
}

public enum ClaimDecisionKind: String, Codable, Equatable, Sendable {
    case confirm
    case dispute
    case correct
}

public enum CaptureReceiptDisposition: String, Codable, Equatable, Sendable {
    case inserted
    case replayed
}

public extension UniversalAccessValidatable {
    func validated() throws -> Self {
        try validate()
        return self
    }
}

private enum UniversalAccessValidation {
    static func require(_ condition: @autoclosure () -> Bool, _ field: String) throws {
        guard condition() else { throw UniversalAccessContractError.invalidField(field) }
    }

    static func nonBlank(_ value: String, maximum: Int, field: String) throws {
        try require(!value.isEmpty && value.count <= maximum && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, field)
    }

    static func stableID(_ value: String, field: String) throws {
        try require(value.count >= 3 && value.count <= 160, field)
        try require(value.range(of: "^[a-z0-9:._-]+$", options: .regularExpression) != nil, field)
    }

    static func hash(_ value: String, field: String) throws {
        try require(value.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil, field)
    }

    static func timestamp(_ value: String, field: String) throws {
        try require(
            value.range(
                of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}(Z|[+-][0-9]{2}:[0-9]{2})$",
                options: .regularExpression
            ) != nil,
            field
        )
    }

    static func sortedUnique(_ values: [String], minimum: Int = 0, maximum: Int, field: String) throws {
        try require(values.count >= minimum && values.count <= maximum, field)
        for index in values.indices where index > values.startIndex {
            try require(values[index - 1] < values[index], field)
        }
    }

    static func base64(_ value: String, minimumBytes: Int = 1, maximumBytes: Int, field: String) throws -> Data {
        guard let data = Data(base64Encoded: value), data.base64EncodedString() == value else {
            throw UniversalAccessContractError.invalidField(field)
        }
        try require(data.count >= minimumBytes && data.count <= maximumBytes, field)
        return data
    }

    static func jsonValue(_ value: JSONValue, depth: Int = 1, nodes: inout Int) throws {
        try require(depth <= 12, "value")
        nodes += 1
        try require(nodes <= 10_000, "value")
        switch value {
        case .string(let string):
            try require(string.count <= 20_000, "value")
        case .number(let number):
            try require(number.isFinite, "value")
        case .bool, .null:
            break
        case .array(let values):
            try require(values.count <= 1_000, "value")
            for item in values { try jsonValue(item, depth: depth + 1, nodes: &nodes) }
        case .object(let object):
            try require(object.count <= 256, "value")
            for (key, item) in object {
                try require(key.count <= 160, "value")
                try jsonValue(item, depth: depth + 1, nodes: &nodes)
            }
        }
    }
}

public struct PairingChallengeRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "clientClass"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let clientClass: UniversalClientClass

    public init(clientClass: UniversalClientClass) {
        schemaVersion = .pairingChallengeRequestV1
        self.clientClass = clientClass
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .pairingChallengeRequestV1, "schemaVersion")
    }
}

public struct PairingCompleteRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "pairingCode", "label", "publicKeyX963", "proofSignature"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let pairingCode: String
    public let label: String
    public let publicKeyX963: String
    public let proofSignature: String

    public init(requestId: String, pairingCode: String, label: String, publicKeyX963: String, proofSignature: String) {
        schemaVersion = .pairingCompleteRequestV1
        self.requestId = requestId
        self.pairingCode = pairingCode
        self.label = label
        self.publicKeyX963 = publicKeyX963
        self.proofSignature = proofSignature
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .pairingCompleteRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.nonBlank(pairingCode, maximum: 256, field: "pairingCode")
        try UniversalAccessValidation.nonBlank(label, maximum: 80, field: "label")
        _ = try UniversalAccessValidation.base64(publicKeyX963, minimumBytes: 65, maximumBytes: 65, field: "publicKeyX963")
        _ = try UniversalAccessValidation.base64(proofSignature, minimumBytes: 64, maximumBytes: 80, field: "proofSignature")
    }
}

public struct KeyRotationRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "expectedKeyVersion", "newPublicKeyX963", "newKeyProofSignature"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let expectedKeyVersion: Int
    public let newPublicKeyX963: String
    public let newKeyProofSignature: String

    public init(requestId: String, expectedKeyVersion: Int, newPublicKeyX963: String, newKeyProofSignature: String) {
        schemaVersion = .keyRotationRequestV1
        self.requestId = requestId
        self.expectedKeyVersion = expectedKeyVersion
        self.newPublicKeyX963 = newPublicKeyX963
        self.newKeyProofSignature = newKeyProofSignature
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .keyRotationRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.require(expectedKeyVersion > 0, "expectedKeyVersion")
        _ = try UniversalAccessValidation.base64(newPublicKeyX963, minimumBytes: 65, maximumBytes: 65, field: "newPublicKeyX963")
        _ = try UniversalAccessValidation.base64(newKeyProofSignature, minimumBytes: 64, maximumBytes: 80, field: "newKeyProofSignature")
    }
}

public struct RecallRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "conversationId", "query", "asOf", "limit"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let conversationId: String
    public let query: String
    public let asOf: String?
    public let limit: Int

    public init(requestId: String, conversationId: String, query: String, asOf: String? = nil, limit: Int) {
        schemaVersion = .recallRequestV1
        self.requestId = requestId
        self.conversationId = conversationId
        self.query = query
        self.asOf = asOf
        self.limit = limit
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .recallRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(conversationId, field: "conversationId")
        try UniversalAccessValidation.nonBlank(query, maximum: 2_000, field: "query")
        if let asOf { try UniversalAccessValidation.timestamp(asOf, field: "asOf") }
        try UniversalAccessValidation.require((1 ... 50).contains(limit), "limit")
    }
}

public struct ClaimCandidateRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "conversationId", "evidenceHandles", "instruction"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let conversationId: String
    public let evidenceHandles: [String]
    public let instruction: String

    public init(requestId: String, conversationId: String, evidenceHandles: [String], instruction: String) {
        schemaVersion = .claimCandidateRequestV1
        self.requestId = requestId
        self.conversationId = conversationId
        self.evidenceHandles = evidenceHandles
        self.instruction = instruction
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .claimCandidateRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(conversationId, field: "conversationId")
        try UniversalAccessValidation.sortedUnique(evidenceHandles, minimum: 1, maximum: 20, field: "evidenceHandles")
        try UniversalAccessValidation.nonBlank(instruction, maximum: 4_000, field: "instruction")
    }
}

public struct ClaimReplacementV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let subjectId: String
    public let predicate: String
    public let kind: ClaimKind
    public let summary: String
    public let value: JSONValue
    public let confidence: Double
    public let validFrom: String?
    public let validTo: String?

    public init(subjectId: String, predicate: String, kind: ClaimKind, summary: String, value: JSONValue, confidence: Double, validFrom: String? = nil, validTo: String? = nil) {
        self.subjectId = subjectId
        self.predicate = predicate
        self.kind = kind
        self.summary = summary
        self.value = value
        self.confidence = confidence
        self.validFrom = validFrom
        self.validTo = validTo
    }

    public func validate() throws {
        try UniversalAccessValidation.stableID(subjectId, field: "subjectId")
        try UniversalAccessValidation.nonBlank(predicate, maximum: 160, field: "predicate")
        try UniversalAccessValidation.nonBlank(summary, maximum: 4_000, field: "summary")
        try UniversalAccessValidation.require(confidence.isFinite && (0 ... 1).contains(confidence), "confidence")
        if let validFrom { try UniversalAccessValidation.timestamp(validFrom, field: "validFrom") }
        if let validTo { try UniversalAccessValidation.timestamp(validTo, field: "validTo") }
        if let validFrom, let validTo { try UniversalAccessValidation.require(validFrom <= validTo, "validTo") }
        var nodes = 0
        try UniversalAccessValidation.jsonValue(value, nodes: &nodes)
    }
}

public enum ClaimDecisionRequestActionV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    case confirm
    case dispute(reason: String)
    case correct(reason: String, replacement: ClaimReplacementV1)

    private enum CodingKeys: String, CodingKey { case kind, reason, replacement }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ClaimDecisionKind.self, forKey: .kind)
        switch kind {
        case .confirm:
            self = .confirm
        case .dispute:
            self = .dispute(reason: try container.decode(String.self, forKey: .reason))
        case .correct:
            self = .correct(
                reason: try container.decode(String.self, forKey: .reason),
                replacement: try container.decode(ClaimReplacementV1.self, forKey: .replacement)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .confirm:
            try container.encode(ClaimDecisionKind.confirm, forKey: .kind)
        case .dispute(let reason):
            try container.encode(ClaimDecisionKind.dispute, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .correct(let reason, let replacement):
            try container.encode(ClaimDecisionKind.correct, forKey: .kind)
            try container.encode(reason, forKey: .reason)
            try container.encode(replacement, forKey: .replacement)
        }
    }

    public func validate() throws {
        switch self {
        case .confirm:
            break
        case .dispute(let reason):
            try UniversalAccessValidation.nonBlank(reason, maximum: 4_000, field: "reason")
        case .correct(let reason, let replacement):
            try UniversalAccessValidation.nonBlank(reason, maximum: 4_000, field: "reason")
            try replacement.validate()
        }
    }
}

public struct ClaimDecisionRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "conversationId", "claimId", "expectedRevision", "decision"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let conversationId: String
    public let claimId: String
    public let expectedRevision: Int
    public let decision: ClaimDecisionRequestActionV1

    public init(requestId: String, conversationId: String, claimId: String, expectedRevision: Int, decision: ClaimDecisionRequestActionV1) {
        schemaVersion = .claimDecisionRequestV1
        self.requestId = requestId
        self.conversationId = conversationId
        self.claimId = claimId
        self.expectedRevision = expectedRevision
        self.decision = decision
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .claimDecisionRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(conversationId, field: "conversationId")
        try UniversalAccessValidation.stableID(claimId, field: "claimId")
        try UniversalAccessValidation.require(expectedRevision > 0, "expectedRevision")
        try decision.validate()
    }
}

public struct DeviceRevocationRequestV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "expectedKeyVersion", "reason"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let expectedKeyVersion: Int
    public let reason: String

    public init(requestId: String, expectedKeyVersion: Int, reason: String) {
        schemaVersion = .deviceRevocationRequestV1
        self.requestId = requestId
        self.expectedKeyVersion = expectedKeyVersion
        self.reason = reason
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .deviceRevocationRequestV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.require(expectedKeyVersion > 0, "expectedKeyVersion")
        try UniversalAccessValidation.nonBlank(reason, maximum: 4_000, field: "reason")
    }
}

public struct AttachmentManifestV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let attachmentId: UUID
    public let ordinal: Int
    public let mediaType: String
    public let byteCount: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentHash: String
    public let classificationHint: UniversalEvidenceClassification

    public init(attachmentId: UUID, ordinal: Int, byteCount: Int, pixelWidth: Int, pixelHeight: Int, contentHash: String) {
        self.attachmentId = attachmentId
        self.ordinal = ordinal
        mediaType = "image/jpeg"
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.contentHash = contentHash
        classificationHint = .restricted
    }

    public func validate() throws {
        try UniversalAccessValidation.require((0 ..< UniversalAccessLimits.maxAttachments).contains(ordinal), "ordinal")
        try UniversalAccessValidation.require(mediaType == "image/jpeg", "mediaType")
        try UniversalAccessValidation.require((1 ... UniversalAccessLimits.maxAttachmentBytes).contains(byteCount), "byteCount")
        try UniversalAccessValidation.require((1 ... 100_000).contains(pixelWidth), "pixelWidth")
        try UniversalAccessValidation.require((1 ... 100_000).contains(pixelHeight), "pixelHeight")
        try UniversalAccessValidation.hash(contentHash, field: "contentHash")
        try UniversalAccessValidation.require(classificationHint == .restricted, "classificationHint")
    }

    fileprivate var canonicalJSONObject: [String: Any] {
        [
            "attachmentId": attachmentId.uuidString.lowercased(),
            "ordinal": ordinal,
            "mediaType": mediaType,
            "byteCount": byteCount,
            "pixelWidth": pixelWidth,
            "pixelHeight": pixelHeight,
            "contentHash": contentHash,
            "classificationHint": classificationHint.rawValue,
        ]
    }
}

public struct CaptureEnvelopeV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "envelopeId", "capturedAt", "source", "clientConversationId", "text", "attachments", "envelopeHash"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let envelopeId: UUID
    public let capturedAt: String
    public let source: CaptureSource
    public let clientConversationId: UUID
    public let text: String?
    public let attachments: [AttachmentManifestV1]
    public let envelopeHash: String

    public init(envelopeId: UUID, capturedAt: String, source: CaptureSource, clientConversationId: UUID, text: String?, attachments: [AttachmentManifestV1], envelopeHash: String) {
        schemaVersion = .captureEnvelopeV1
        self.envelopeId = envelopeId
        self.capturedAt = capturedAt
        self.source = source
        self.clientConversationId = clientConversationId
        self.text = text
        self.attachments = attachments
        self.envelopeHash = envelopeHash
    }

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .captureEnvelopeV1, "schemaVersion")
        try UniversalAccessValidation.timestamp(capturedAt, field: "capturedAt")
        if let text {
            try UniversalAccessValidation.require(text.count <= UniversalAccessLimits.maxCaptureTextCharacters, "text")
            try UniversalAccessValidation.require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "text")
        }
        try UniversalAccessValidation.require(text != nil || !attachments.isEmpty, "capture")
        try UniversalAccessValidation.require(attachments.count <= UniversalAccessLimits.maxAttachments, "attachments")
        var ids = Set<UUID>()
        for (index, attachment) in attachments.enumerated() {
            try attachment.validate()
            try UniversalAccessValidation.require(attachment.ordinal == index, "attachments.ordinal")
            try UniversalAccessValidation.require(ids.insert(attachment.attachmentId).inserted, "attachments.attachmentId")
        }
        try UniversalAccessValidation.hash(envelopeHash, field: "envelopeHash")
    }

    public func recomputedHash() throws -> String {
        var object: [String: Any] = [
            "schemaVersion": schemaVersion.rawValue,
            "envelopeId": envelopeId.uuidString.lowercased(),
            "capturedAt": capturedAt,
            "source": source.rawValue,
            "clientConversationId": clientConversationId.uuidString.lowercased(),
            "attachments": attachments.map(\.canonicalJSONObject),
        ]
        if let text { object["text"] = text }
        return "sha256:\(try CanonicalJSON.sha256(ofJSONObject: object))"
    }
}

public struct CaptureAttachmentBodyV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let attachmentId: UUID
    public let contentBase64: String

    public init(attachmentId: UUID, contentBase64: String) {
        self.attachmentId = attachmentId
        self.contentBase64 = contentBase64
    }

    public func validate() throws {
        _ = try UniversalAccessValidation.base64(contentBase64, maximumBytes: UniversalAccessLimits.maxAttachmentBytes, field: "contentBase64")
    }
}

public struct CaptureUploadV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["envelope", "attachmentBodies"]
    public let envelope: CaptureEnvelopeV1
    public let attachmentBodies: [CaptureAttachmentBodyV1]

    public init(envelope: CaptureEnvelopeV1, attachmentBodies: [CaptureAttachmentBodyV1]) {
        self.envelope = envelope
        self.attachmentBodies = attachmentBodies
    }

    public func validate() throws {
        try envelope.validate()
        try UniversalAccessValidation.require(attachmentBodies.count == envelope.attachments.count, "attachmentBodies")
        var seen = Set<UUID>()
        for (index, body) in attachmentBodies.enumerated() {
            try body.validate()
            try UniversalAccessValidation.require(seen.insert(body.attachmentId).inserted, "attachmentBodies.attachmentId")
            let manifest = envelope.attachments[index]
            try UniversalAccessValidation.require(body.attachmentId == manifest.attachmentId, "attachmentBodies.attachmentId")
            let bytes = try UniversalAccessValidation.base64(body.contentBase64, maximumBytes: UniversalAccessLimits.maxAttachmentBytes, field: "attachmentBodies.contentBase64")
            try UniversalAccessValidation.require(bytes.count == manifest.byteCount, "attachmentBodies.byteCount")
        }
        let encoded = try UniversalAccessJSON.encoder.encode(self)
        try UniversalAccessValidation.require(encoded.count <= UniversalAccessLimits.maxCaptureHTTPBytes, "captureUpload")
    }
}

public struct UniversalEvidenceHandleV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let domain: UniversalAccessDomain
    public let kind: String
    public let classification: UniversalEvidenceClassification
    public let observedAt: String
    public let contentHash: String?
    public let accessGrant: String
    public let grantExpiresAt: String

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        try UniversalAccessValidation.require(kind.range(of: "^[a-z0-9:._-]{1,80}$", options: .regularExpression) != nil, "kind")
        try UniversalAccessValidation.timestamp(observedAt, field: "observedAt")
        if let contentHash { try UniversalAccessValidation.hash(contentHash, field: "contentHash") }
        try UniversalAccessValidation.require((16 ... 512).contains(accessGrant.count), "accessGrant")
        try UniversalAccessValidation.timestamp(grantExpiresAt, field: "grantExpiresAt")
    }
}

public struct CanonicalEvidenceReferenceV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let contentHash: String?

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        if let contentHash { try UniversalAccessValidation.hash(contentHash, field: "contentHash") }
    }
}

public struct CaptureReceiptV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "envelopeId", "envelopeHash", "captureId", "conversationId", "conversationItemId", "evidence", "eventId", "acceptedAt", "requestReceiptId", "disposition"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let envelopeId: UUID
    public let envelopeHash: String
    public let captureId: String
    public let conversationId: String
    public let conversationItemId: String
    public let evidence: [UniversalEvidenceHandleV1]
    public let eventId: String
    public let acceptedAt: String
    public let requestReceiptId: String
    public let disposition: CaptureReceiptDisposition

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .captureReceiptV1, "schemaVersion")
        try UniversalAccessValidation.hash(envelopeHash, field: "envelopeHash")
        for (field, value) in [("captureId", captureId), ("conversationId", conversationId), ("conversationItemId", conversationItemId), ("eventId", eventId), ("requestReceiptId", requestReceiptId)] {
            try UniversalAccessValidation.stableID(value, field: field)
        }
        try UniversalAccessValidation.require((1 ... UniversalAccessLimits.maxAttachments + 1).contains(evidence.count), "evidence")
        for handle in evidence { try handle.validate() }
        try UniversalAccessValidation.timestamp(acceptedAt, field: "acceptedAt")
    }
}

public struct ServerIdentityV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let serverId: String
    public let displayName: String
    public let origin: String
    public let tlsFingerprint: String

    public func validate() throws {
        try UniversalAccessValidation.stableID(serverId, field: "serverId")
        try UniversalAccessValidation.nonBlank(displayName, maximum: 80, field: "displayName")
        try UniversalAccessValidation.require(origin.hasPrefix("https://") && origin.count <= 2_048, "origin")
        try UniversalAccessValidation.hash(tlsFingerprint, field: "tlsFingerprint")
    }
}

public struct PairingChallengeV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "challengeId", "pairingCode", "clientClass", "serverIdentity", "scopeProfile", "expiresAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let challengeId: String
    public let pairingCode: String
    public let clientClass: UniversalClientClass
    public let serverIdentity: ServerIdentityV1
    public let scopeProfile: UniversalScopeProfile
    public let expiresAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .pairingChallengeV1, "schemaVersion")
        try UniversalAccessValidation.stableID(challengeId, field: "challengeId")
        try UniversalAccessValidation.nonBlank(pairingCode, maximum: 256, field: "pairingCode")
        try serverIdentity.validate()
        try UniversalAccessValidation.require(clientClass.rawValue == scopeProfile.rawValue, "scopeProfile")
        try UniversalAccessValidation.timestamp(expiresAt, field: "expiresAt")
    }
}

public struct PairingReceiptV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "receiptId", "deviceId", "clientClass", "label", "keyVersion", "serverIdentity", "scopeProfile", "scopes", "domains", "defaultConversationId", "pairedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let receiptId: String
    public let deviceId: String
    public let clientClass: UniversalClientClass
    public let label: String
    public let keyVersion: Int
    public let serverIdentity: ServerIdentityV1
    public let scopeProfile: UniversalScopeProfile
    public let scopes: [String]
    public let domains: [UniversalAccessDomain]
    public let defaultConversationId: String
    public let pairedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .pairingReceiptV1, "schemaVersion")
        try UniversalAccessValidation.stableID(receiptId, field: "receiptId")
        try UniversalAccessValidation.stableID(deviceId, field: "deviceId")
        try UniversalAccessValidation.nonBlank(label, maximum: 80, field: "label")
        try UniversalAccessValidation.require(keyVersion > 0, "keyVersion")
        try serverIdentity.validate()
        try UniversalAccessValidation.require(clientClass.rawValue == scopeProfile.rawValue, "scopeProfile")
        try UniversalAccessValidation.sortedUnique(scopes, minimum: 1, maximum: 20, field: "scopes")
        let expected = scopeProfile == .reach ? reachUniversalAccessScopes : lodestarUniversalAccessScopes
        try UniversalAccessValidation.require(scopes == expected, "scopes")
        try UniversalAccessValidation.sortedUnique(domains.map(\.rawValue), minimum: 1, maximum: 2, field: "domains")
        try UniversalAccessValidation.require(domains == [.inbox, .personal], "domains")
        try UniversalAccessValidation.stableID(defaultConversationId, field: "defaultConversationId")
        try UniversalAccessValidation.timestamp(pairedAt, field: "pairedAt")
    }
}

public struct DevicePolicyV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let profile: UniversalScopeProfile
    public let scopes: [String]
    public let domains: [UniversalAccessDomain]
    public let maximumClassification: UniversalEvidenceClassification

    public func validate() throws {
        try UniversalAccessValidation.sortedUnique(scopes, minimum: 1, maximum: 20, field: "scopes")
        let expected = profile == .reach ? reachUniversalAccessScopes : lodestarUniversalAccessScopes
        try UniversalAccessValidation.require(scopes == expected, "scopes")
        try UniversalAccessValidation.sortedUnique(domains.map(\.rawValue), minimum: 1, maximum: 2, field: "domains")
    }
}

public struct ConversationThreadV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let title: String
    public let createdAt: String
    public let updatedAt: String
    public let lastItemId: String?

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        try UniversalAccessValidation.nonBlank(title, maximum: 200, field: "title")
        try UniversalAccessValidation.timestamp(createdAt, field: "createdAt")
        try UniversalAccessValidation.timestamp(updatedAt, field: "updatedAt")
        if let lastItemId { try UniversalAccessValidation.stableID(lastItemId, field: "lastItemId") }
    }
}

public struct ConversationItemV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let conversationId: String
    public let kind: ConversationItemKind
    public let observedAt: String
    public let effectiveAt: String
    public let producer: String
    public let displayText: String
    public let freshness: UniversalFreshness
    public let evidence: [UniversalEvidenceHandleV1]
    public let payloadHash: String

    public func validate() throws {
        for (field, value) in [("id", id), ("conversationId", conversationId), ("producer", producer)] {
            try UniversalAccessValidation.stableID(value, field: field)
        }
        try UniversalAccessValidation.timestamp(observedAt, field: "observedAt")
        try UniversalAccessValidation.timestamp(effectiveAt, field: "effectiveAt")
        try UniversalAccessValidation.require(displayText.count <= 20_000, "displayText")
        try UniversalAccessValidation.require(evidence.count <= 100, "evidence")
        for handle in evidence { try handle.validate() }
        try UniversalAccessValidation.hash(payloadHash, field: "payloadHash")
    }
}

public struct CursorPageV1<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable, UniversalAccessRootObject {
    public static var allowedRootKeys: Set<String> { ["schemaVersion", "items", "nextCursor"] }
    public let schemaVersion: UniversalAccessSchemaVersion
    public let items: [Item]
    public let nextCursor: String?

    public init(items: [Item], nextCursor: String? = nil) {
        schemaVersion = .cursorPageV1
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct BootstrapResponseV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "serverIdentity", "deviceId", "policy", "defaultConversation", "conversationCursor", "captureCursor", "generatedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let serverIdentity: ServerIdentityV1
    public let deviceId: String
    public let policy: DevicePolicyV1
    public let defaultConversation: ConversationThreadV1
    public let conversationCursor: String?
    public let captureCursor: String?
    public let generatedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .bootstrapResponseV1, "schemaVersion")
        try serverIdentity.validate()
        try UniversalAccessValidation.stableID(deviceId, field: "deviceId")
        try policy.validate()
        try defaultConversation.validate()
        if let conversationCursor { try UniversalAccessValidation.require((1 ... 2_048).contains(conversationCursor.count), "conversationCursor") }
        if let captureCursor { try UniversalAccessValidation.require((1 ... 2_048).contains(captureCursor.count), "captureCursor") }
        try UniversalAccessValidation.timestamp(generatedAt, field: "generatedAt")
    }
}

public struct RecallResultV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let captureId: String?
    public let excerpt: String
    public let uncertainty: String
    public let capturedAt: String
    public let evidence: [UniversalEvidenceHandleV1]

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        if let captureId { try UniversalAccessValidation.stableID(captureId, field: "captureId") }
        try UniversalAccessValidation.require((1 ... 4_000).contains(excerpt.count), "excerpt")
        try UniversalAccessValidation.require(uncertainty.count <= 1_000, "uncertainty")
        try UniversalAccessValidation.timestamp(capturedAt, field: "capturedAt")
        try UniversalAccessValidation.require((1 ... 20).contains(evidence.count), "evidence")
        for handle in evidence { try handle.validate() }
    }
}

public struct RecallNarrativeV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let text: String
    public let citations: [String]

    public func validate() throws {
        try UniversalAccessValidation.nonBlank(text, maximum: 8_000, field: "text")
        try UniversalAccessValidation.sortedUnique(citations, minimum: 1, maximum: 20, field: "citations")
    }
}

public struct RecallResponseV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "conversationId", "generatedAt", "effectiveAsOf", "freshness", "contextPackHash", "results", "redactions", "gaps", "queryItemId", "resultItemId", "narrative", "synthesisUnavailable"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let conversationId: String
    public let generatedAt: String
    public let effectiveAsOf: String
    public let freshness: UniversalFreshness
    public let contextPackHash: String
    public let results: [RecallResultV1]
    public let redactions: [String]
    public let gaps: [String]
    public let queryItemId: String
    public let resultItemId: String
    public let narrative: RecallNarrativeV1?
    public let synthesisUnavailable: Bool

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .recallResponseV1, "schemaVersion")
        for (field, value) in [("requestId", requestId), ("conversationId", conversationId), ("queryItemId", queryItemId), ("resultItemId", resultItemId)] {
            try UniversalAccessValidation.stableID(value, field: field)
        }
        try UniversalAccessValidation.timestamp(generatedAt, field: "generatedAt")
        try UniversalAccessValidation.timestamp(effectiveAsOf, field: "effectiveAsOf")
        try UniversalAccessValidation.hash(contextPackHash, field: "contextPackHash")
        try UniversalAccessValidation.require(results.count <= 50, "results")
        for result in results { try result.validate() }
        for (field, values) in [("redactions", redactions), ("gaps", gaps)] {
            try UniversalAccessValidation.require(values.count <= 100 && values.allSatisfy { (1 ... 500).contains($0.count) }, field)
        }
        if let narrative {
            try narrative.validate()
            let grants = Set(results.flatMap { $0.evidence.map(\.accessGrant) })
            try UniversalAccessValidation.require(narrative.citations.allSatisfy(grants.contains), "narrative.citations")
        }
    }
}

public enum EvidenceResponseDisposition: String, Codable, Equatable, Sendable {
    case content
    case metadata
    case redacted
}

public struct EvidenceResponseV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "evidence", "disposition", "mediaType", "text", "contentBase64", "redactionReason"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let evidence: UniversalEvidenceHandleV1
    public let disposition: EvidenceResponseDisposition
    public let mediaType: String?
    public let text: String?
    public let contentBase64: String?
    public let redactionReason: String?

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .evidenceResponseV1, "schemaVersion")
        try evidence.validate()
        if let mediaType { try UniversalAccessValidation.require((1 ... 160).contains(mediaType.count), "mediaType") }
        if let text { try UniversalAccessValidation.require(text.count <= UniversalAccessLimits.maxCaptureTextCharacters, "text") }
        if let contentBase64 { _ = try UniversalAccessValidation.base64(contentBase64, maximumBytes: UniversalAccessLimits.maxAttachmentBytes, field: "contentBase64") }
        if disposition == .redacted {
            guard let redactionReason else { throw UniversalAccessContractError.invalidField("redactionReason") }
            try UniversalAccessValidation.nonBlank(redactionReason, maximum: 500, field: "redactionReason")
        } else {
            try UniversalAccessValidation.require(redactionReason == nil, "redactionReason")
        }
        if disposition != .content {
            try UniversalAccessValidation.require(text == nil && contentBase64 == nil, "content")
        }
    }
}

public struct PulseContextItemV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let text: String
    public let freshness: UniversalFreshness
    public let gaps: [String]
    public let evidence: [UniversalEvidenceHandleV1]

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        try UniversalAccessValidation.require((1 ... 4_000).contains(text.count), "text")
        try UniversalAccessValidation.require(gaps.count <= 20 && gaps.allSatisfy { (1 ... 500).contains($0.count) }, "gaps")
        try UniversalAccessValidation.require(evidence.count <= 20, "evidence")
        for handle in evidence { try handle.validate() }
    }
}

public struct PulseItemV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let id: String
    public let kind: ConversationItemKind
    public let title: String
    public let summary: String
    public let effectiveAt: String
    public let freshness: UniversalFreshness
    public let gaps: [String]
    public let evidence: [UniversalEvidenceHandleV1]

    public func validate() throws {
        try UniversalAccessValidation.stableID(id, field: "id")
        try UniversalAccessValidation.nonBlank(title, maximum: 200, field: "title")
        try UniversalAccessValidation.nonBlank(summary, maximum: 4_000, field: "summary")
        try UniversalAccessValidation.timestamp(effectiveAt, field: "effectiveAt")
        try UniversalAccessValidation.require(gaps.count <= 20 && gaps.allSatisfy { (1 ... 500).contains($0.count) }, "gaps")
        try UniversalAccessValidation.require(evidence.count <= 20, "evidence")
        for handle in evidence { try handle.validate() }
    }
}

public struct QuickRecallV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let conversationId: String
    public let placeholder: String

    public func validate() throws {
        try UniversalAccessValidation.stableID(conversationId, field: "conversationId")
        try UniversalAccessValidation.nonBlank(placeholder, maximum: 200, field: "placeholder")
    }
}

public struct PulseSnapshotV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "generatedAt", "freshness", "recentItems", "currentClaims", "unresolvedQuestions", "quickRecall", "claimExceptionCount", "gaps"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let generatedAt: String
    public let freshness: UniversalFreshness
    public let recentItems: [PulseItemV1]
    public let currentClaims: [PulseContextItemV1]
    public let unresolvedQuestions: [PulseContextItemV1]
    public let quickRecall: QuickRecallV1
    public let claimExceptionCount: Int
    public let gaps: [String]

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .pulseSnapshotV1, "schemaVersion")
        try UniversalAccessValidation.timestamp(generatedAt, field: "generatedAt")
        for item in recentItems { try item.validate() }
        for item in currentClaims { try item.validate() }
        for item in unresolvedQuestions { try item.validate() }
        try UniversalAccessValidation.require(recentItems.count <= 20 && currentClaims.count <= 20 && unresolvedQuestions.count <= 20, "items")
        try quickRecall.validate()
        try UniversalAccessValidation.require(claimExceptionCount >= 0, "claimExceptionCount")
        try UniversalAccessValidation.require(gaps.count <= 100 && gaps.allSatisfy { (1 ... 500).contains($0.count) }, "gaps")
    }
}

public struct ClaimCandidateV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let claimId: String
    public let revision: Int
    public let subjectId: String
    public let predicate: String
    public let kind: ClaimKind
    public let summary: String
    public let value: JSONValue
    public let confidence: Double
    public let status: String
    public let evidence: [UniversalEvidenceHandleV1]
    public let createdAt: String

    public func validate() throws {
        try UniversalAccessValidation.stableID(claimId, field: "claimId")
        try UniversalAccessValidation.require(revision > 0, "revision")
        let replacement = ClaimReplacementV1(subjectId: subjectId, predicate: predicate, kind: kind, summary: summary, value: value, confidence: confidence)
        try replacement.validate()
        try UniversalAccessValidation.require(status == "candidate", "status")
        try UniversalAccessValidation.require((1 ... 20).contains(evidence.count), "evidence")
        for handle in evidence { try handle.validate() }
        try UniversalAccessValidation.timestamp(createdAt, field: "createdAt")
    }
}

public struct ClaimCandidateReceiptV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "conversationId", "candidates", "conversationItemId", "createdAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let conversationId: String
    public let candidates: [ClaimCandidateV1]
    public let conversationItemId: String?
    public let createdAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .claimCandidateReceiptV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(conversationId, field: "conversationId")
        try UniversalAccessValidation.require(candidates.count <= 20, "candidates")
        for candidate in candidates { try candidate.validate() }
        if let conversationItemId { try UniversalAccessValidation.stableID(conversationItemId, field: "conversationItemId") }
        try UniversalAccessValidation.timestamp(createdAt, field: "createdAt")
    }
}

public enum ClaimExceptionStatus: String, Codable, Equatable, Sendable {
    case candidate
    case disputed
}

public struct ClaimExceptionV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let claimId: String
    public let revision: Int
    public let status: ClaimExceptionStatus
    public let summary: String
    public let reason: String?
    public let evidence: [UniversalEvidenceHandleV1]
    public let updatedAt: String

    public func validate() throws {
        try UniversalAccessValidation.stableID(claimId, field: "claimId")
        try UniversalAccessValidation.require(revision > 0, "revision")
        try UniversalAccessValidation.nonBlank(summary, maximum: 4_000, field: "summary")
        if let reason { try UniversalAccessValidation.nonBlank(reason, maximum: 4_000, field: "reason") }
        try UniversalAccessValidation.require((1 ... 20).contains(evidence.count), "evidence")
        for handle in evidence { try handle.validate() }
        try UniversalAccessValidation.timestamp(updatedAt, field: "updatedAt")
    }
}

public struct ClaimDecisionV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "decisionId", "requestId", "conversationId", "claimId", "expectedRevision", "decision", "reason", "priorRevisionId", "resultingRevisionIds", "replacementClaimId", "actorDeviceId", "authority", "requestHash", "evidence", "conversationItemId", "decidedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let decisionId: String
    public let requestId: String
    public let conversationId: String
    public let claimId: String
    public let expectedRevision: Int
    public let decision: ClaimDecisionKind
    public let reason: String?
    public let priorRevisionId: String
    public let resultingRevisionIds: [String]
    public let replacementClaimId: String?
    public let actorDeviceId: String
    public let authority: String
    public let requestHash: String
    public let evidence: [CanonicalEvidenceReferenceV1]
    public let conversationItemId: String
    public let decidedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .claimDecisionV1, "schemaVersion")
        for (field, value) in [
            ("decisionId", decisionId), ("requestId", requestId), ("conversationId", conversationId),
            ("claimId", claimId), ("priorRevisionId", priorRevisionId), ("actorDeviceId", actorDeviceId),
            ("conversationItemId", conversationItemId),
        ] {
            try UniversalAccessValidation.stableID(value, field: field)
        }
        try UniversalAccessValidation.require(expectedRevision > 0, "expectedRevision")
        if decision == .confirm {
            try UniversalAccessValidation.require(reason == nil, "reason")
        } else if let reason {
            try UniversalAccessValidation.nonBlank(reason, maximum: 4_000, field: "reason")
        } else {
            throw UniversalAccessContractError.invalidField("reason")
        }
        try UniversalAccessValidation.sortedUnique(resultingRevisionIds, minimum: 1, maximum: 2, field: "resultingRevisionIds")
        if let replacementClaimId { try UniversalAccessValidation.stableID(replacementClaimId, field: "replacementClaimId") }
        try UniversalAccessValidation.require((decision == .correct) == (replacementClaimId != nil), "replacementClaimId")
        try UniversalAccessValidation.require(authority == "human", "authority")
        try UniversalAccessValidation.hash(requestHash, field: "requestHash")
        try UniversalAccessValidation.require((1 ... 20).contains(evidence.count), "evidence")
        for reference in evidence { try reference.validate() }
        try UniversalAccessValidation.timestamp(decidedAt, field: "decidedAt")
    }
}

public struct DeviceSummaryV1: Codable, Equatable, Sendable, UniversalAccessValidatable {
    public let deviceId: String
    public let label: String
    public let clientClass: UniversalClientClass
    public let scopeProfile: UniversalScopeProfile
    public let keyVersion: Int
    public let createdAt: String
    public let lastAuthenticatedAt: String?
    public let revokedAt: String?

    public func validate() throws {
        try UniversalAccessValidation.stableID(deviceId, field: "deviceId")
        try UniversalAccessValidation.nonBlank(label, maximum: 80, field: "label")
        try UniversalAccessValidation.require(clientClass.rawValue == scopeProfile.rawValue, "scopeProfile")
        try UniversalAccessValidation.require(keyVersion > 0, "keyVersion")
        try UniversalAccessValidation.timestamp(createdAt, field: "createdAt")
        if let lastAuthenticatedAt { try UniversalAccessValidation.timestamp(lastAuthenticatedAt, field: "lastAuthenticatedAt") }
        if let revokedAt { try UniversalAccessValidation.timestamp(revokedAt, field: "revokedAt") }
    }
}

public struct DeviceListResponseV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "devices", "generatedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let devices: [DeviceSummaryV1]
    public let generatedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .deviceListResponseV1, "schemaVersion")
        try UniversalAccessValidation.require(devices.count <= 100, "devices")
        for device in devices { try device.validate() }
        try UniversalAccessValidation.timestamp(generatedAt, field: "generatedAt")
    }
}

public struct KeyRotationReceiptV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "deviceId", "keyVersion", "rotatedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let deviceId: String
    public let keyVersion: Int
    public let rotatedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .keyRotationReceiptV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(deviceId, field: "deviceId")
        try UniversalAccessValidation.require(keyVersion > 0, "keyVersion")
        try UniversalAccessValidation.timestamp(rotatedAt, field: "rotatedAt")
    }
}

public struct DeviceRevocationReceiptV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "deviceId", "keyVersion", "revokedAt"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String
    public let deviceId: String
    public let keyVersion: Int
    public let revokedAt: String

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .deviceRevocationReceiptV1, "schemaVersion")
        try UniversalAccessValidation.stableID(requestId, field: "requestId")
        try UniversalAccessValidation.stableID(deviceId, field: "deviceId")
        try UniversalAccessValidation.require(keyVersion > 0, "keyVersion")
        try UniversalAccessValidation.timestamp(revokedAt, field: "revokedAt")
    }
}

public enum UniversalAccessErrorCategory: String, Codable, Equatable, Sendable {
    case badRequest = "bad_request"
    case bodyTooLarge = "body_too_large"
    case captureConflict = "capture_conflict"
    case claimChanged = "claim_changed"
    case forbidden
    case integrityFailed = "integrity_failed"
    case notFound = "not_found"
    case pairingExpired = "pairing_expired"
    case pairingInvalid = "pairing_invalid"
    case rateLimited = "rate_limited"
    case replayRejected = "replay_rejected"
    case revoked
    case unauthenticated
    case unavailable
}

public struct UniversalAccessErrorEnvelopeV1: Codable, Equatable, Sendable, UniversalAccessRootObject, UniversalAccessValidatable {
    public static let allowedRootKeys: Set<String> = ["schemaVersion", "requestId", "category", "message", "retryable", "serverTime"]
    public let schemaVersion: UniversalAccessSchemaVersion
    public let requestId: String?
    public let category: UniversalAccessErrorCategory
    public let message: String
    public let retryable: Bool
    public let serverTime: String?

    public func validate() throws {
        try UniversalAccessValidation.require(schemaVersion == .universalAccessErrorV1, "schemaVersion")
        if let requestId { try UniversalAccessValidation.stableID(requestId, field: "requestId") }
        try UniversalAccessValidation.nonBlank(message, maximum: 500, field: "message")
        if let serverTime { try UniversalAccessValidation.timestamp(serverTime, field: "serverTime") }
    }
}
