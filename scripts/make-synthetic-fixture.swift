// Run with the macOS Swift toolchain. Contains only fictional, non-personal text.
import AppKit
import Foundation

let size = NSSize(width: 1000, height: 600)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 600,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 52, weight: .regular),
    .foregroundColor: NSColor.black
]
for (index, line) in ["SYNTHETIC STORE", "TEST ITEM      12.34", "TOTAL          12.34"].enumerated() {
    (line as NSString).draw(at: NSPoint(x: 70, y: 450 - index * 130), withAttributes: attributes)
}
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "RcpLens/Resources/synthetic-receipt.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
