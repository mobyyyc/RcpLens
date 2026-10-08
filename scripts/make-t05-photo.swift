// Synthetic-only fixture metadata distinguishes it from existing Simulator Photos. No receipt fields are inferred.
import Foundation
import ImageIO
import UniformTypeIdentifiers
let base = FileManager.default.currentDirectoryPath + "/"
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath:base+"RcpLens/Resources/synthetic-receipt.png") as CFURL,nil)!
let image = CGImageSourceCreateImageAtIndex(src,0,nil)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath:base+"docs/evidence/t05/synthetic-photo.jpg") as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,image,[kCGImagePropertyExifDictionary:[kCGImagePropertyExifDateTimeOriginal:"2036:10:07 12:00:00",kCGImagePropertyExifDateTimeDigitized:"2036:10:07 12:00:00"],kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFDateTime:"2036:10:07 12:00:00"]] as CFDictionary)
precondition(CGImageDestinationFinalize(dest))
print("Dated synthetic picker fixture prepared")
