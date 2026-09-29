import AppKit
let img = NSImage(contentsOfFile: "Scripts/release/.smoke-bar.png")!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
    if let c = rep.colorAt(x: x, y: y), c.redComponent > 0.85, c.blueComponent > 0.85, c.greenComponent < 0.3 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
if maxX >= 0 { print("magenta block: \(maxX - minX + 1) x \(maxY - minY + 1) px") } else { print("NOT FOUND") }
