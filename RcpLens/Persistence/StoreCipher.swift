import Foundation
import CryptoKit

struct ReceiptStoreCipher: Sendable {
    private let key: SymmetricKey
    init(key: Data) throws {
        guard key.count == 32 else { throw ReceiptStoreError.invalidKey }
        self.key = SymmetricKey(data: key)
    }

    func seal(_ data: Data, context: String) throws -> Data {
        // CryptoKit supplies a fresh random 96-bit nonce for each sealing operation.
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: Data(context.utf8)).combined else {
            throw ReceiptStoreError.authenticationFailed
        }
        return combined
    }

    func open(_ data: Data, context: String) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key,
                                    authenticating: Data(context.utf8))
        } catch { throw ReceiptStoreError.authenticationFailed }
    }

    static func receiptContext(_ id: UUID) -> String { "RcpLens/receipt/v1/" + id.uuidString }
    static func assetContext(_ id: UUID, owner: UUID) -> String {
        "RcpLens/asset/v1/" + owner.uuidString + "/" + id.uuidString
    }
    static let manifestContext = "RcpLens/manifest/v1"
    static let manifest = Data("RcpLens authenticated local store v1".utf8)
}
