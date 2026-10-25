import AppKit
let output = CommandLine.arguments[1]
let space = CGColorSpaceCreateDeviceRGB()
let drawing = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: drawing, flipped: false)
NSColor(red: 0.14, green: 0.34, blue: 0.25, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
NSColor(red: 0.95, green: 0.96, blue: 0.84, alpha: 1).setFill()
for (index, height) in [0.20, 0.36, 0.52, 0.36, 0.20].enumerated() {
    let width: CGFloat = 63
    let rect = NSRect(x: 261 + CGFloat(index) * 108, y: 512 * (1 - height), width: width, height: 1024 * height)
    NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
}
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: drawing.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
