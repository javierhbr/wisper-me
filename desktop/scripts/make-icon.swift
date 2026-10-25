import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        NSColor(red: 0.14, green: 0.34, blue: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92),
                     xRadius: s * 0.22, yRadius: s * 0.22).fill()
        NSColor(red: 0.95, green: 0.96, blue: 0.84, alpha: 1).setFill()
        let heights: [CGFloat] = [0.20, 0.36, 0.52, 0.36, 0.20]
        for (index, height) in heights.enumerated() {
            let width = s * 0.062
            let rect = NSRect(x: s * (0.255 + CGFloat(index) * 0.106), y: s * (1 - height) / 2, width: width, height: s * height)
            NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
        }
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try representation.representation(using: .png, properties: [:])!.write(
            to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("Icon conversion failed") }
try FileManager.default.removeItem(at: iconset)
