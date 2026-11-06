// Renders the Dad Flow app icon (1024x1024 PNG): cream squircle, teal sticker, lemon waveform.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
func c(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// macOS icon grid: 824pt body inset by 100.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
c(0xFDF7E7).setFill(); squircle.fill()
c(0x14433D).setStroke(); squircle.lineWidth = 14; squircle.stroke()

// Tilted teal sticker
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: 6 * .pi / 180)
let sticker = NSBezierPath(roundedRect: NSRect(x: -270, y: -270, width: 540, height: 540), xRadius: 120, yRadius: 120)
c(0x0B2B27).setFill()
let lip = NSBezierPath(roundedRect: NSRect(x: -270, y: -290, width: 540, height: 540), xRadius: 120, yRadius: 120)
lip.fill()
c(0x14433D).setFill(); sticker.fill()
let heights: [CGFloat] = [130, 260, 360, 210, 310, 160]
let barW: CGFloat = 46, gap: CGFloat = 30
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
for (i, h) in heights.enumerated() {
    let x = -total / 2 + CGFloat(i) * (barW + gap)
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: -h / 2, width: barW, height: h), xRadius: barW / 2, yRadius: barW / 2)
    c(0xFDF4B5).setFill(); bar.fill()
}
ctx.restoreGState()

// Cherry dot sticker (the "voice" spark)
let dot = NSBezierPath(ovalIn: NSRect(x: 700, y: 690, width: 150, height: 150))
c(0xFEBAC4).setFill(); dot.fill()
c(0x14433D).setStroke(); dot.lineWidth = 12; dot.stroke()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
