import Foundation
import Security

/// Holds one secret string.
public protocol SecretStore: AnyObject {
    func get() -> String?
    /// Stores the value; nil removes it.
    func set(_ value: String?)
}

public final class InMemorySecretStore: SecretStore {
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public func get() -> String? { value }
    public func set(_ value: String?) { self.value = value }
}

/// Generic-password item in the login Keychain.
public final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String

    public init(service: String = "com.lorenz.finderwheel", account: String = "mistral-api-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func get() -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { NSLog("FinderWheel: could not store key in Keychain, status \(status)") }
    }
}
