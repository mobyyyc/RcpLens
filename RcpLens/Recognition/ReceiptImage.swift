import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ReceiptImage: Sendable {
    let bytes: Data
    let mediaType: String
    let orientation: CGImagePropertyOrientation
    let pixelWidth: Int
    let pixelHeight: Int

    static func decode(_ bytes: Data) throws -> ReceiptImage {
        guard !bytes.isEmpty, bytes.count <= ReceiptStore.maximumAssetBytes else { throw ImportFailure.tooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), let mime = type.preferredMIMEType,
              ["image/png", "image/jpeg", "image/heic", "image/heif"].contains(mime),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0,
              width <= 60_000, height <= 60_000, Int64(width) * Int64(height) <= 120_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
            throw ImportFailure.unsupportedImage
        }
        let orientation = CGImagePropertyOrientation(rawValue: (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        return ReceiptImage(bytes: bytes, mediaType: mime, orientation: orientation, pixelWidth: width, pixelHeight: height)
    }
}

enum ImportFailure: Error, Sendable {
    case tooLarge, unsupportedImage, unavailableFile, noText, recognitionFailed
    var message: String {
        switch self {
        case .tooLarge: "Choose an image under 32 MB. Very large images cannot be stored."
        case .unsupportedImage: "This image could not be decoded. Choose a single PNG, JPEG or HEIC image."
        case .unavailableFile: "The image could not be accessed. It may be unavailable or access may have been denied. Try Files or another photo."
        case .noText: "No readable text was found. You can retry or enter the receipt manually while viewing the original."
        case .recognitionFailed: "Text recognition stopped. You can retry or enter the receipt manually while viewing the original."
        }
    }
}
