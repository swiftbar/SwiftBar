import AppKit
let px = 54
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.magenta.setFill()
NSRect(x: 0, y: 0, width: px, height: px).fill()
NSGraphicsContext.restoreGraphicsState()
rep.size = NSSize(width: 27, height: 27) // 144dpi: 54px at 27pt
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Scripts/release/.smoke-icon.png"))
print(png.base64EncodedString())
