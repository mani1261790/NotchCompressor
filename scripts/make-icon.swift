import AppKit

// Original geometric artwork: a notch and three compression destinations.
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
        NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.44, blue: 0.94, alpha: 1), ending: NSColor(srgbRed: 0.10, green: 0.16, blue: 0.41, alpha: 1))!.draw(in: tile, angle: 90)
        let panel = NSBezierPath(roundedRect: NSRect(x: 181, y: 293, width: 662, height: 442), xRadius: 85, yRadius: 85)
        NSColor(srgbRed: 0.035, green: 0.055, blue: 0.105, alpha: 1).setFill()
        panel.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        panel.lineWidth = 4
        panel.stroke()
        let notch = NSBezierPath(roundedRect: NSRect(x: 365, y: 638, width: 294, height: 154), xRadius: 44, yRadius: 44)
        NSColor(srgbRed: 0.03, green: 0.045, blue: 0.085, alpha: 1).setFill()
        notch.fill()
        for x in [CGFloat(318), 512, 706] {
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: x, y: 574))
            arrow.line(to: NSPoint(x: x, y: 405))
            arrow.move(to: NSPoint(x: x - 48, y: 453))
            arrow.line(to: NSPoint(x: x, y: 405))
            arrow.line(to: NSPoint(x: x + 48, y: 453))
            arrow.lineWidth = 24
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor(srgbRed: 0.78, green: 0.92, blue: 1, alpha: 1).setStroke()
            arrow.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
