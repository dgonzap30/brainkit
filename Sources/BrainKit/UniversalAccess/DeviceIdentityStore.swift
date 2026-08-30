import CryptoKit
import Foundation
import Security

public typealias DeviceProfileV1 = UniversalScopeProfile

public struct DeviceIdentityMetadataV1: Codable, Equatable, Sendable {
    public let serverOrigin: URL
    public let serverIdentity: String
    public let tlsSPKISHA256: String
    public let deviceId: String
    public let label: String
    public let profile: DeviceProfileV1
    public let scopes: [String]
    public let domains: [UniversalAccessDomain]
    public let keyVersion: Int

    public init(
        serverOrigin: URL,
        serverIdentity: String,
        tlsSPKISHA256: String,
        deviceId: String,
        label: String,
        profile: DeviceProfileV1,
        scopes: [String],
        domains: [UniversalAccessDomain],
        keyVersion: Int
    ) {
        self.serverOrigin = serverOrigin
        self.serverIdentity = serverIdentity
        self.tlsSPKISHA256 = tlsSPKISHA256
        self.deviceId = deviceId
        self.label = label
        self.profile = profile
        self.scopes = scopes
        self.domains = domains
        self.keyVersion = keyVersion
    }

    public func validate() throws {
        guard let components = URLComponents(url: serverOrigin, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              serverIdentity.range(of: "^[a-z][a-z0-9-]{1,47}:[a-z0-9][a-z0-9._:-]{0,159}$", options: .regularExpression) != nil,
              deviceId.range(of: "^[a-z][a-z0-9-]{1,47}:[a-z0-9][a-z0-9._:-]{0,159}$", options: .regularExpression) != nil,
              tlsSPKISHA256.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil,
              (1 ... 80).contains(label.count),
              scopes == (profile == .reach ? reachUniversalAccessScopes : lodestarUniversalAccessScopes),
              domains == [.inbox, .personal],
              keyVersion > 0
        else {
            throw UniversalAccessError.invalidRequest
        }
    }
}

public struct PendingDeviceIdentityV1: Sendable {
    public let label: String
    public let profile: DeviceProfileV1
    public let signer: any UniversalAccessSigner

    public init(label: String, profile: DeviceProfileV1, signer: any UniversalAccessSigner) throws {
        guard (1 ... 80).contains(label.count),
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              signer.publicKeyX963.count == 65
        else {
            throw UniversalAccessError.invalidRequest
        }
        self.label = label
        self.profile = profile
        self.signer = signer
    }

    public var publicKeyX963: Data { signer.publicKeyX963 }
}

public struct DeviceIdentityV1: Sendable {
    public let metadata: DeviceIdentityMetadataV1
    public let signer: any UniversalAccessSigner

    public init(metadata: DeviceIdentityMetadataV1, signer: any UniversalAccessSigner) {
        self.metadata = metadata
        self.signer = signer
    }

    public init(receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws {
        try receipt.validate()
        guard receipt.scopeProfile == pending.profile,
              receipt.label == pending.label,
              receipt.clientClass.rawValue == pending.profile.rawValue,
              let origin = URL(string: receipt.serverIdentity.origin)
        else {
            throw UniversalAccessError.invalidRequest
        }
        let metadata = DeviceIdentityMetadataV1(
            serverOrigin: origin,
            serverIdentity: receipt.serverIdentity.serverId,
            tlsSPKISHA256: receipt.serverIdentity.tlsFingerprint,
            deviceId: receipt.deviceId,
            label: receipt.label,
            profile: receipt.scopeProfile,
            scopes: receipt.scopes,
            domains: receipt.domains,
            keyVersion: receipt.keyVersion
        )
        try metadata.validate()
        self.init(metadata: metadata, signer: pending.signer)
    }

    public init(
        rotationReceipt receipt: KeyRotationReceiptV1,
        current: DeviceIdentityV1,
        pending: PendingDeviceIdentityV1
    ) throws {
        try receipt.validate()
        try current.metadata.validate()
        guard receipt.deviceId == current.metadata.deviceId,
              receipt.keyVersion == current.metadata.keyVersion + 1,
              pending.label == current.metadata.label,
              pending.profile == current.metadata.profile,
              pending.publicKeyX963 != current.signer.publicKeyX963
        else {
            throw UniversalAccessError.invalidRequest
        }
        let metadata = DeviceIdentityMetadataV1(
            serverOrigin: current.metadata.serverOrigin,
            serverIdentity: current.metadata.serverIdentity,
            tlsSPKISHA256: current.metadata.tlsSPKISHA256,
            deviceId: current.metadata.deviceId,
            label: current.metadata.label,
            profile: current.metadata.profile,
            scopes: current.metadata.scopes,
            domains: current.metadata.domains,
            keyVersion: receipt.keyVersion
        )
        try metadata.validate()
        self.init(metadata: metadata, signer: pending.signer)
    }
}

public struct PendingKeyRotationV1: Sendable {
    public let request: KeyRotationRequestV1
    public let label: String
    public let profile: DeviceProfileV1
    public let pending: PendingDeviceIdentityV1?

    public init(
        request: KeyRotationRequestV1,
        pending: PendingDeviceIdentityV1
    ) throws {
        try self.init(
            storedRequest: request,
            label: pending.label,
            profile: pending.profile,
            pending: pending
        )
    }

    fileprivate init(
        storedRequest request: KeyRotationRequestV1,
        label: String,
        profile: DeviceProfileV1,
        pending: PendingDeviceIdentityV1?
    ) throws {
        try request.validate()
        guard (1 ... 80).contains(label.count),
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UniversalAccessError.credentialUnavailable
        }
        if let pending {
            guard pending.label == label,
                  pending.profile == profile,
                  Data(base64Encoded: request.newPublicKeyX963) == pending.publicKeyX963
            else {
                throw UniversalAccessError.credentialUnavailable
            }
        }
        self.request = request
        self.label = label
        self.profile = profile
        self.pending = pending
    }
}

public protocol DeviceIdentityStoring: Sendable {
    func load() throws -> DeviceIdentityV1?
    func create(label: String, profile: DeviceProfileV1) throws -> PendingDeviceIdentityV1
    func savePairing(_ receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws
    func saveRotation(_ receipt: KeyRotationReceiptV1, pending: PendingDeviceIdentityV1) throws
    func loadPendingRotation() throws -> PendingKeyRotationV1?
    func savePendingRotation(_ rotation: PendingKeyRotationV1) throws
    func clearPendingRotation(requestId: String) throws
    func removeOperationalCredential() throws
}

public final class SystemDeviceIdentityStore: DeviceIdentityStoring, @unchecked Sendable {
    private enum Account {
        static let metadata = "universal-access.metadata.v1"
        static let keyKind = "universal-access.key-kind.v1"
        static let key = "universal-access.operational-key.v1"
        static let pendingRotation = "universal-access.pending-rotation.v1"
        static let pendingRotationKeyKind = "universal-access.pending-rotation-key-kind.v1"
        static let pendingRotationKey = "universal-access.pending-rotation-key.v1"
    }

    private struct StoredPendingRotationV1: Codable {
        let request: KeyRotationRequestV1
        let label: String
        let profile: DeviceProfileV1
    }

    private let keychain: DeviceIdentityKeychain

    public init(service: String = "com.lojik.lodestar.universal-access") {
        keychain = DeviceIdentityKeychain(service: service)
    }

    public func load() throws -> DeviceIdentityV1? {
        guard let metadataData = try keychain.data(account: Account.metadata) else { return nil }
        guard let kindData = try keychain.data(account: Account.keyKind),
              let kind = String(data: kindData, encoding: .utf8),
              let keyData = try keychain.data(account: Account.key)
        else {
            throw UniversalAccessError.credentialUnavailable
        }

        let metadata: DeviceIdentityMetadataV1
        do {
            metadata = try JSONDecoder().decode(DeviceIdentityMetadataV1.self, from: metadataData)
            try metadata.validate()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let signer = try restoreSigner(kind: kind, keyData: keyData)
        return DeviceIdentityV1(metadata: metadata, signer: signer)
    }

    public func create(label: String, profile: DeviceProfileV1) throws -> PendingDeviceIdentityV1 {
        let signer: any UniversalAccessSigner
        if SecureEnclave.isAvailable {
            do {
                signer = try SecureEnclaveUniversalAccessSigner()
            } catch {
                signer = P256SoftwareUniversalAccessSigner()
            }
        } else {
            signer = P256SoftwareUniversalAccessSigner()
        }
        return try PendingDeviceIdentityV1(label: label, profile: profile, signer: signer)
    }

    public func savePairing(_ receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws {
        let identity = try DeviceIdentityV1(receipt: receipt, pending: pending)
        try persist(identity: identity, pending: pending)
    }

    public func saveRotation(_ receipt: KeyRotationReceiptV1, pending: PendingDeviceIdentityV1) throws {
        guard let current = try load() else { throw UniversalAccessError.notPaired }
        let identity = try DeviceIdentityV1(
            rotationReceipt: receipt,
            current: current,
            pending: pending
        )
        try persist(identity: identity, pending: pending)
    }

    public func loadPendingRotation() throws -> PendingKeyRotationV1? {
        guard let metadataData = try keychain.data(account: Account.pendingRotation) else {
            return nil
        }
        let stored: StoredPendingRotationV1
        do {
            stored = try JSONDecoder().decode(StoredPendingRotationV1.self, from: metadataData)
            try stored.request.validate()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let kindData = try keychain.data(account: Account.pendingRotationKeyKind)
        let keyData = try keychain.data(account: Account.pendingRotationKey)
        let pending: PendingDeviceIdentityV1?
        if let kindData,
           let kind = String(data: kindData, encoding: .utf8),
           let keyData {
            do {
                pending = try PendingDeviceIdentityV1(
                    label: stored.label,
                    profile: stored.profile,
                    signer: restoreSigner(kind: kind, keyData: keyData)
                )
            } catch {
                pending = nil
            }
        } else {
            pending = nil
        }
        return try PendingKeyRotationV1(
            storedRequest: stored.request,
            label: stored.label,
            profile: stored.profile,
            pending: pending
        )
    }

    public func savePendingRotation(_ rotation: PendingKeyRotationV1) throws {
        guard let pending = rotation.pending,
              let storedSigner = pending.signer as? any StoredUniversalAccessSigner
        else {
            throw UniversalAccessError.credentialUnavailable
        }
        if let existing = try loadPendingRotation() {
            guard existing.request == rotation.request,
                  existing.label == rotation.label,
                  existing.profile == rotation.profile,
                  existing.pending?.publicKeyX963 == pending.publicKeyX963
            else {
                throw UniversalAccessError.credentialUnavailable
            }
            return
        }

        let metadataData: Data
        let keyData: Data
        do {
            metadataData = try JSONEncoder().encode(StoredPendingRotationV1(
                request: rotation.request,
                label: rotation.label,
                profile: rotation.profile
            ))
            keyData = try storedSigner.protectedStorageRepresentation()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        let accounts = [
            Account.pendingRotationKey,
            Account.pendingRotationKeyKind,
            Account.pendingRotation,
        ]
        let previous: [(String, Data?)]
        do {
            previous = try accounts.map { ($0, try keychain.data(account: $0)) }
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        do {
            try keychain.set(keyData, account: Account.pendingRotationKey)
            try keychain.set(
                Data(storedSigner.storageKind.utf8),
                account: Account.pendingRotationKeyKind
            )
            try keychain.set(metadataData, account: Account.pendingRotation)
        } catch {
            for (account, data) in previous.reversed() {
                if let data {
                    try? keychain.set(data, account: account)
                } else {
                    try? keychain.remove(account: account)
                }
            }
            throw UniversalAccessError.credentialUnavailable
        }
    }

    public func clearPendingRotation(requestId: String) throws {
        guard let metadataData = try keychain.data(account: Account.pendingRotation) else {
            return
        }
        let stored: StoredPendingRotationV1
        do {
            stored = try JSONDecoder().decode(StoredPendingRotationV1.self, from: metadataData)
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
        guard stored.request.requestId == requestId else {
            throw UniversalAccessError.credentialUnavailable
        }
        do {
            try keychain.remove(account: Account.pendingRotationKey)
            try keychain.remove(account: Account.pendingRotationKeyKind)
            try keychain.remove(account: Account.pendingRotation)
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
    }

    private func persist(identity: DeviceIdentityV1, pending: PendingDeviceIdentityV1) throws {
        guard let storedSigner = pending.signer as? any StoredUniversalAccessSigner else {
            throw UniversalAccessError.credentialUnavailable
        }

        let metadataData: Data
        let keyData: Data
        do {
            metadataData = try JSONEncoder().encode(identity.metadata)
            keyData = try storedSigner.protectedStorageRepresentation()
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        let previous: [(String, Data?)]
        do {
            previous = try [Account.key, Account.keyKind, Account.metadata].map {
                ($0, try keychain.data(account: $0))
            }
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }

        do {
            try keychain.set(keyData, account: Account.key)
            try keychain.set(Data(storedSigner.storageKind.utf8), account: Account.keyKind)
            try keychain.set(metadataData, account: Account.metadata)
        } catch {
            for (account, data) in previous.reversed() {
                if let data {
                    try? keychain.set(data, account: account)
                } else {
                    try? keychain.remove(account: account)
                }
            }
            throw UniversalAccessError.credentialUnavailable
        }
    }

    public func removeOperationalCredential() throws {
        var firstError: Error?
        for account in [
            Account.metadata,
            Account.keyKind,
            Account.key,
            Account.pendingRotation,
            Account.pendingRotationKeyKind,
            Account.pendingRotationKey,
        ] {
            do { try keychain.remove(account: account) } catch { firstError = firstError ?? error }
        }
        if firstError != nil { throw UniversalAccessError.credentialUnavailable }
    }

    private func restoreSigner(
        kind: String,
        keyData: Data
    ) throws -> any UniversalAccessSigner {
        do {
            switch kind {
            case "p256-secure-enclave-v1":
                return try SecureEnclaveUniversalAccessSigner(protectedRepresentation: keyData)
            case "p256-software-v1":
                return try P256SoftwareUniversalAccessSigner(rawPrivateKey: keyData)
            default:
                throw UniversalAccessError.credentialUnavailable
            }
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
    }
}

private struct DeviceIdentityKeychain: Sendable {
    let service: String

    func data(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw UniversalAccessError.credentialUnavailable
        }
        return data
    }

    func set(_ data: Data, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw UniversalAccessError.credentialUnavailable
        }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw UniversalAccessError.credentialUnavailable
        }
    }

    func remove(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UniversalAccessError.credentialUnavailable
        }
    }
}
