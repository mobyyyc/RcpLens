import Foundation
import Security

/// Implementations must never manufacture a replacement for an existing unreadable key.
protocol ReceiptStoreKeyProvider: Sendable {
    func loadKey() throws -> Data?
    func createKey() throws -> Data
}

struct KeychainReceiptStoreKey: ReceiptStoreKeyProvider {
    let service: String
    let account: String

    init(service: String = "com.mobyyyc.RcpLens.receipt-store", account: String = "local-v1") {
        self.service = service; self.account = account
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func loadKey() throws -> Data? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReceiptStoreError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw ReceiptStoreError.invalidKey }
        return data
    }

    func createKey() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw ReceiptStoreError.keychain(status) }
        var item = identity
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecValueData as String] = bytes
        let added = SecItemAdd(item as CFDictionary, nil)
        // An overlapping first-open may have created the key. Read it; never update it.
        if added == errSecDuplicateItem {
            guard let existing = try loadKey() else { throw ReceiptStoreError.missingKey }
            return existing
        }
        guard added == errSecSuccess else { throw ReceiptStoreError.keychain(added) }
        return bytes
    }
}

enum ReceiptStoreError: Error, Equatable {
    case missingKey, invalidKey, authenticationFailed, corruptStore, unsupportedSchema(Int64)
    case keychain(Int32), database(Int32), closed, notFound, editConflict, invalidAsset, sizeLimit
    case injectedFailure, protectionUnavailable
}
