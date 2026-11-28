import AppKit

// Match Lunamo's icon-and-wordmark composition, using NotchCompressor's blue palette.
let output =
    CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site/assets/notchcompressor-wordmark-card.png"
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1200, height: 600)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(
    starting: NSColor(srgbRed: 0.98, green: 0.99, blue: 1, alpha: 1),
    ending: NSColor(srgbRed: 0.85, green: 0.90, blue: 1, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: 1200, height: 600), angle: 0)
let title = "NotchCompressor" as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 82, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.07, green: 0.12, blue: 0.23, alpha: 1),
    .kern: -3,
]
let size = title.size(withAttributes: attributes)
let iconSize: CGFloat = 140
let left = (1200 - iconSize - 24 - size.width) / 2
NSImage(contentsOfFile: "site/assets/icon.png")!.draw(in: NSRect(x: left, y: 230, width: iconSize, height: iconSize))
title.draw(at: NSPoint(x: left + iconSize + 24, y: (600 - size.height) / 2), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
