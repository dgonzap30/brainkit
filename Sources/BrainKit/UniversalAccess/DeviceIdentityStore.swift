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
}

public protocol DeviceIdentityStoring: Sendable {
    func load() throws -> DeviceIdentityV1?
    func create(label: String, profile: DeviceProfileV1) throws -> PendingDeviceIdentityV1
    func savePairing(_ receipt: PairingReceiptV1, pending: PendingDeviceIdentityV1) throws
    func removeOperationalCredential() throws
}

public final class SystemDeviceIdentityStore: DeviceIdentityStoring, @unchecked Sendable {
    private enum Account {
        static let metadata = "universal-access.metadata.v1"
        static let keyKind = "universal-access.key-kind.v1"
        static let key = "universal-access.operational-key.v1"
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

        let signer: any UniversalAccessSigner
        do {
            switch kind {
            case "p256-secure-enclave-v1":
                signer = try SecureEnclaveUniversalAccessSigner(protectedRepresentation: keyData)
            case "p256-software-v1":
                signer = try P256SoftwareUniversalAccessSigner(rawPrivateKey: keyData)
            default:
                throw UniversalAccessError.credentialUnavailable
            }
        } catch {
            throw UniversalAccessError.credentialUnavailable
        }
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

        do {
            try keychain.set(keyData, account: Account.key)
            try keychain.set(Data(storedSigner.storageKind.utf8), account: Account.keyKind)
            try keychain.set(metadataData, account: Account.metadata)
        } catch {
            try? removeOperationalCredential()
            throw UniversalAccessError.credentialUnavailable
        }
    }

    public func removeOperationalCredential() throws {
        var firstError: Error?
        for account in [Account.metadata, Account.keyKind, Account.key] {
            do { try keychain.remove(account: account) } catch { firstError = firstError ?? error }
        }
        if firstError != nil { throw UniversalAccessError.credentialUnavailable }
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
