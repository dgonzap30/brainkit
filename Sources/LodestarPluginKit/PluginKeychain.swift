import Foundation
import Security

/// Token store — abstracted so tests use an in-memory impl and never touch the system keychain.
/// Verbatim port of ReachCore's `KeychainStore`/`SystemKeychain` into the shared plugin product; the
/// only difference is the default service string (`com.lojik.lodestar.plugin`, not `...reach`).
public protocol KeychainStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

/// Security-framework backed store for the real app. Generic-password items under one service.
public final class SystemKeychain: KeychainStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.lojik.lodestar.plugin") { self.service = service }

    public func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, forKey key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
