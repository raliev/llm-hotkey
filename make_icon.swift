import Cocoa

// Renders the 1024×1024 app icon PNG: a rounded gradient tile with the
// same SF Symbol the menu-bar icon uses. Usage: make_icon <out.png>

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Standard macOS icon grid: 824pt tile centered in 1024 canvas
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
           ending: NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.92, alpha: 1))!
    .draw(in: path, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
if let symbol = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { r in
        symbol.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
