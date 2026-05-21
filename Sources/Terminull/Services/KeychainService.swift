import Foundation
import Security

protocol KeychainManaging: AnyObject {
    func saveSecret(_ secret: String, account: String) throws
    func readSecret(account: String) throws -> String?
    func hasSecret(account: String) -> Bool
    func deleteSecret(account: String) throws
}

final class KeychainService: KeychainManaging {
    static let serviceName = "com.synfinner.Terminull.ssh-key-passphrase"

    func saveSecret(_ secret: String, account: String) throws {
        do {
            try saveSecret(secret, account: account, usesDataProtectionKeychain: true)
            try? deleteSecret(account: account, usesDataProtectionKeychain: false)
        } catch let error as KeychainError where Self.shouldFallBackToLoginKeychain(status: error.status) {
            try saveSecret(secret, account: account, usesDataProtectionKeychain: false)
        }
    }

    private func saveSecret(
        _ secret: String,
        account: String,
        usesDataProtectionKeychain: Bool
    ) throws {
        let data = Data(secret.utf8)
        let query = Self.query(account: account, usesDataProtectionKeychain: usesDataProtectionKeychain)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
            return
        }

        throw KeychainError(status: status)
    }

    func readSecret(account: String) throws -> String? {
        do {
            if let secret = try readSecret(account: account, usesDataProtectionKeychain: true) {
                return secret
            }
        } catch let error as KeychainError where Self.shouldFallBackToLoginKeychain(status: error.status) {
            // Ad-hoc and non-entitled builds cannot access the macOS data-protection keychain.
        }
        return try readSecret(account: account, usesDataProtectionKeychain: false)
    }

    func hasSecret(account: String) -> Bool {
        (try? readSecret(account: account)) != nil
    }

    func deleteSecret(account: String) throws {
        do {
            try deleteSecret(account: account, usesDataProtectionKeychain: true)
        } catch let error as KeychainError where Self.shouldFallBackToLoginKeychain(status: error.status) {
            // Still remove the fallback login-keychain item when data-protection access is unavailable.
        }
        try deleteSecret(account: account, usesDataProtectionKeychain: false)
    }

    static func shouldFallBackToLoginKeychain(status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
    }

    private static func query(account: String, usesDataProtectionKeychain: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func readSecret(account: String, usesDataProtectionKeychain: Bool) throws -> String? {
        var query = Self.query(account: account, usesDataProtectionKeychain: usesDataProtectionKeychain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(account: String, usesDataProtectionKeychain: Bool) throws {
        let query = Self.query(account: account, usesDataProtectionKeychain: usesDataProtectionKeychain)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain error \(status)"
    }
}
