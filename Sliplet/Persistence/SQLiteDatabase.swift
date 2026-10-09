import Foundation
import SQLite3

/// Private to a ReceiptStore actor except synchronous initialization and focused test fixtures.
/// No SQLite error descriptions or SQL bind values escape this boundary.
final class ReceiptSQLiteDatabase: @unchecked Sendable {
    enum Value { case integer(Int64), text(String), blob(Data), null }
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, create: Bool) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_FILEPROTECTION_COMPLETE
            | (create ? SQLITE_OPEN_CREATE : 0)
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw ReceiptStoreError.database(status)
        }
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { if let handle { sqlite3_close(handle) } }
    func close() throws {
        guard let handle else { return }
        let result = sqlite3_close(handle)
        guard result == SQLITE_OK else { throw ReceiptStoreError.database(result) }
        self.handle = nil
    }

    @discardableResult
    func run(_ sql: String, _ values: [Value] = []) throws -> [[Value]] {
        guard let handle else { throw ReceiptStoreError.closed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw ReceiptStoreError.database(prepared) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let number): status = sqlite3_bind_int64(statement, index, number)
            case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, transient)
            case .blob(let data):
                guard data.count <= Int(Int32.max) else { throw ReceiptStoreError.sizeLimit }
                status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw ReceiptStoreError.database(status) }
        }
        var rows: [[Value]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw ReceiptStoreError.database(status) }
            var row: [Value] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_TEXT:
                    guard let pointer = sqlite3_column_text(statement, column) else { throw ReceiptStoreError.corruptStore }
                    row.append(.text(String(cString: pointer)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if count == 0 { row.append(.blob(Data())) }
                    else {
                        guard let pointer = sqlite3_column_blob(statement, column) else { throw ReceiptStoreError.corruptStore }
                        row.append(.blob(Data(bytes: pointer, count: count)))
                    }
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
    }

    func integer(_ sql: String) throws -> Int64 {
        guard let row = try run(sql).first, case .integer(let result) = row.first else {
            throw ReceiptStoreError.corruptStore
        }
        return result
    }

    func transaction<T>(permit: ReceiptOperationPermit? = nil, _ body: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do {
            let result = try body()
            if let permit { _ = try permit.committing { try run("COMMIT") } }
            else { try run("COMMIT") }
            return result
        } catch {
            // If rollback itself fails, the connection must not be reused.
            do { try run("ROLLBACK") } catch { try? close() }
            throw error
        }
    }
}
