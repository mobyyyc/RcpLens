import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Portable, password-derived protection. Device storage keys are never exported.
enum ReceiptBackupError: Error, Equatable, LocalizedError {
    case password, unsupported, invalidArchive, authentication, limit, assetCollision, changedPreview, unavailable
    var errorDescription: String? {
        switch self {
        case .password: "Use a backup password of at least 12 characters, no more than 1,024 UTF-8 bytes."
        case .unsupported: "This backup version is not supported. Keep the file and try a newer Sliplet version."
        case .invalidArchive: "This backup is incomplete or invalid. Your wallet has not changed."
        case .authentication: "The password is incorrect or this backup is damaged. Your wallet has not changed."
        case .limit: "This backup exceeds a supported limit: 1,000 receipts or 256 MB. Your wallet has not changed."
        case .assetCollision: "Original-image ownership conflicts with this wallet. Restore stopped without changing it."
        case .changedPreview: "The wallet changed after the preview. Choose the backup again to review an updated preview."
        case .unavailable: "The selected file could not be accessed. Choose an available backup in Files and try again."
        }
    }
}

struct ReceiptBackupManifest: Codable, Sendable {
    let version: Int
    let storeSchema: Int64
    let createdAt: Date
    let receiptCount: Int
    let walletSettings: ReceiptWalletSettings
}
struct ReceiptBackupPreview: Equatable, Sendable {
    let total: Int
    let added: Int
    let skipped: Int
    let conflicts: Int
}

/// Only an encrypted, fully validated isolated store survives preparation. No password is retained.
final class ReceiptPreparedBackup: @unchecked Sendable {
    let directory: URL
    let key: Data
    let manifest: ReceiptBackupManifest
    init(directory: URL, key: Data, manifest: ReceiptBackupManifest) {
        self.directory = directory; self.key = key; self.manifest = manifest
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Fixed v1 cost avoids attacker-controlled KDF work. Each bounded frame is authenticated with
/// its sequence number and the exact header; the encrypted manifest fixes the number of frames.
/// No compression, paths, ZIP extraction, or plaintext temporary receipts are used.
enum ReceiptBackupArchive {
    static let maximumBytes = 256 * 1024 * 1024
    static let maximumReceipts = 1_000
    static let rounds: UInt32 = 600_000
    static let magic = Data("SLIPLETBK001".utf8)
    static let headerBytes = magic.count + 16

    static func validatePassword(_ password: String) throws {
        guard password.count >= 12, password.utf8.count <= 1_024 else { throw ReceiptBackupError.password }
    }
    static func randomKey() throws -> Data {
        var bytes = Data(count: 32)
        guard bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }) == errSecSuccess else {
            throw ReceiptBackupError.unavailable
        }
        return bytes
    }
    static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
        try validatePassword(password)
        var input = Data(password.utf8), result = Data(count: 32)
        defer { input.resetBytes(in: 0..<input.count); result.resetBytes(in: 0..<result.count) }
        let status = input.withUnsafeBytes { p in salt.withUnsafeBytes { s in result.withUnsafeMutableBytes { r in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: CChar.self), p.count,
                s.baseAddress!.assumingMemoryBound(to: UInt8.self), s.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                rounds, r.baseAddress!.assumingMemoryBound(to: UInt8.self), r.count)
        } } }
        guard status == kCCSuccess else { throw ReceiptBackupError.unavailable }
        return SymmetricKey(data: result)
    }
    static func protectedDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
        var mutable = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SlipletBackup-" + UUID().uuidString, isDirectory: true)
        try protectedDirectory(url); return url
    }
    private static func sequence(_ index: UInt64, header: Data) -> Data {
        var big = index.bigEndian
        return header + withUnsafeBytes(of: &big) { Data($0) }
    }
    final class Writer {
        private let handle: FileHandle
        private let header: Data
        private let key: SymmetricKey
        private var index: UInt64 = 0
        private var written = headerBytes
        init(url: URL, password: String) throws {
            let salt = try randomKey().prefix(16)
            header = magic + salt; key = try derive(password, salt: salt)
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600]) else { throw ReceiptBackupError.unavailable }
            handle = try FileHandle(forWritingTo: url)
            try handle.write(contentsOf: header)
        }
        deinit { try? handle.close() }
        func write(_ bytes: Data, maximum: Int, permit: ReceiptOperationPermit) throws {
            try permit.check()
            guard !bytes.isEmpty, bytes.count <= maximum else { throw ReceiptBackupError.limit }
            let box = try AES.GCM.seal(bytes, using: key, authenticating: sequence(index, header: header))
            guard let combined = box.combined, written + 4 + combined.count <= maximumBytes else { throw ReceiptBackupError.limit }
            var count = UInt32(combined.count).bigEndian
            try handle.write(contentsOf: withUnsafeBytes(of: &count) { Data($0) })
            try handle.write(contentsOf: combined)
            written += 4 + combined.count; index += 1
            try permit.check()
        }
        func finish() throws { try handle.synchronize(); try handle.close() }
    }
    final class Reader {
        private let handle: FileHandle
        private let header: Data
        private let key: SymmetricKey
        private var index: UInt64 = 0
        private var readCount = headerBytes
        init(url: URL, password: String) throws {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else { throw ReceiptBackupError.unavailable }
            guard size >= headerBytes, size <= maximumBytes else { throw ReceiptBackupError.limit }
            handle = try FileHandle(forReadingFrom: url)
            header = try Self.exact(handle, count: headerBytes)
            guard header.prefix(magic.count) == magic else { throw ReceiptBackupError.unsupported }
            key = try derive(password, salt: header.suffix(16))
        }
        deinit { try? handle.close() }
        private static func exact(_ handle: FileHandle, count: Int) throws -> Data {
            var data = Data()
            while data.count < count {
                guard let part = try handle.read(upToCount: count - data.count), !part.isEmpty else { throw ReceiptBackupError.invalidArchive }
                data.append(part)
            }
            return data
        }
        func read(maximum: Int, permit: ReceiptOperationPermit) throws -> Data {
            try permit.check()
            let prefix = try Self.exact(handle, count: 4)
            let size = prefix.reduce(0) { ($0 << 8) | Int($1) }
            guard size >= 28, size <= maximum + 28, readCount + 4 + size <= maximumBytes else { throw ReceiptBackupError.limit }
            let combined = try Self.exact(handle, count: size)
            let bytes: Data
            do { bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: sequence(index, header: header)) }
            catch { throw ReceiptBackupError.authentication }
            readCount += 4 + size; index += 1
            try permit.check(); return bytes
        }
        func finish() throws {
            guard try handle.read(upToCount: 1)?.isEmpty != false else { throw ReceiptBackupError.invalidArchive }
            try handle.close()
        }
    }
}

struct ReceiptBackupTemporaryKey: ReceiptStoreKeyProvider {
    let bytes: Data
    func loadKey() throws -> Data? { bytes }
    func createKey() throws -> Data { bytes }
}
enum ReceiptBackupPreparation {
    /// Only the explicit picker URL is coordinated and copied; the copy is still password encrypted.
    static func prepare(url: URL, password: String, permit: ReceiptOperationPermit) async throws -> ReceiptPreparedBackup {
        try permit.check()
        let directory = try ReceiptBackupArchive.temporaryDirectory()
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: directory) } }
        let input = directory.appendingPathComponent("selected.slipletbackup")
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?, copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { selected in
            do {
                try permit.check()
                let values = try selected.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let count = values.fileSize else { throw ReceiptBackupError.unavailable }
                guard count >= ReceiptBackupArchive.headerBytes, count <= ReceiptBackupArchive.maximumBytes else { throw ReceiptBackupError.limit }
                guard FileManager.default.createFile(atPath: input.path, contents: nil,
                    attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600]) else { throw ReceiptBackupError.unavailable }
                let source = try FileHandle(forReadingFrom: selected), target = try FileHandle(forWritingTo: input)
                defer { try? source.close(); try? target.close() }
                var copied = 0
                while let chunk = try source.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try permit.check(); copied += chunk.count
                    guard copied <= ReceiptBackupArchive.maximumBytes else { throw ReceiptBackupError.limit }
                    try target.write(contentsOf: chunk)
                }
                try target.synchronize()
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600], ofItemAtPath: input.path)
            } catch { copyError = error }
        }
        if let copyError { throw copyError }
        if coordinationError != nil { throw ReceiptBackupError.unavailable }
        try permit.check()
        let key = try ReceiptBackupArchive.randomKey()
        let store = try ReceiptStore(directory: directory, keyProvider: ReceiptBackupTemporaryKey(bytes: key))
        let manifest: ReceiptBackupManifest
        do { manifest = try await store.stageBackup(from: input, password: password, permit: permit); try await store.close() }
        catch { try? await store.close(); throw error }
        try FileManager.default.removeItem(at: input)
        try permit.check(); keep = true
        return ReceiptPreparedBackup(directory: directory, key: key, manifest: manifest)
    }
}
