import Foundation

/// Source text at the recognition boundary. Parsing and user corrections belong elsewhere.
struct RecognizedText: Sendable {
    let lines: [String]
}
