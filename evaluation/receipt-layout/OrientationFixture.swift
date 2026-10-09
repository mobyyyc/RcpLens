import Foundation
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// Fictional text at opposite ends of a tall page; JPEGs differ only in the
// inverse raw-pixel transform and EXIF orientation needed for upright display.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 900, height = 2400
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
func draw(_ text: String, x: Double, y: Double) {
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 42, nil)
    let attributed = NSAttributedString(string:text, attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font,
                                    NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)])
    context.textPosition = CGPoint(x:x, y:y)
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
}
draw("COSTCO CAD SYNTHETIC", x:60,y:2270)
draw("123456 茶 TEA 2.50", x:60,y:2100)
draw("654321 米 RICE 3.50", x:60,y:1250)
draw("TOTAL 6.00", x:570,y:90)
let upright = CIImage(cgImage:context.makeImage()!)
let renderer = CIContext(options: [.useSoftwareRenderer:true])
for raw in UInt32(1)...UInt32(8) {
    let orientation = CGImagePropertyOrientation(rawValue:raw)!
    let inverse: CGImagePropertyOrientation = orientation == .left ? .right : (orientation == .right ? .left : orientation)
    let stored = upright.oriented(inverse)
    guard let cg = renderer.createCGImage(stored, from:stored.extent) else { throw CocoaError(.coderInvalidValue) }
    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("orientation-\(raw).jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation:raw, kCGImageDestinationLossyCompressionQuality:1.0] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}
print("created: eight fictional orientation JPEGs")
