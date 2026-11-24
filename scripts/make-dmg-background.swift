import AppKit

let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ja"
guard ["ja", "en"].contains(language) else {
    fatalError("DMG language must be ja or en")
}
let size = NSSize(width: 660, height: 400)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
func text(_ value: String, y: CGFloat, size fontSize: CGFloat, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (value as NSString).draw(
        in: NSRect(x: 30, y: y, width: 600, height: 38),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color, .paragraphStyle: style,
        ])
}
text("NotchCompressor", y: 330, size: 25, color: .black)
text("→", y: 190, size: 36, color: .darkGray)
text(
    language == "ja" ? "アプリを右のApplicationsへドラッグ" : "Drag the app to Applications on the right",
    y: 76, size: 17, color: .black)
text(
    language == "ja" ? "コピー後、Applicationsから開いてください" : "After copying, open the app from Applications",
    y: 40, size: 13, color: .darkGray)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
