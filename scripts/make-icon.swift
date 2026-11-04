import AppKit
// Draws the app icon (a screen with a notch) and writes an .iconset next to the given output dir.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let body = NSBezierPath(roundedRect: r.insetBy(dx: s * 0.06, dy: s * 0.06), xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.30, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.10, green: 0.62, blue: 0.95, alpha: 1)])!
            .draw(in: body, angle: -60)
        // pill notch hanging from the top edge
        let w = s * 0.46, h = s * 0.17
        let notch = NSBezierPath(roundedRect: NSRect(x: (s - w) / 2, y: s * 0.94 - h, width: w, height: h + s * 0.2), xRadius: h * 0.5, yRadius: h * 0.5)
        NSGraphicsContext.saveGraphicsState(); body.addClip(); NSColor.black.setFill(); notch.fill(); NSGraphicsContext.restoreGraphicsState()
        // little music bars in the notch
        NSColor.white.withAlphaComponent(0.9).setFill()
        for i in 0..<3 {
            let bh = h * [0.35, 0.6, 0.45][i]
            NSBezierPath(roundedRect: NSRect(x: s * 0.5 - w * 0.12 + CGFloat(i) * w * 0.12, y: s * 0.94 - h * 0.5 - bh / 2, width: w * 0.06, height: bh), xRadius: w * 0.03, yRadius: w * 0.03).fill()
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64), ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512), ("512", 512), ("512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name.replacingOccurrences(of: "@2x", with: "")).png".replacingOccurrences(of: "icon_\(name.replacingOccurrences(of: "@2x", with: "")).png", with: name.contains("@2x") ? "icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))@2x.png" : "icon_\(name)x\(name).png")))
}
