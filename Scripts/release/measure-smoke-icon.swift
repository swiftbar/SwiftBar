import AppKit
let capturePath = CommandLine.arguments.dropFirst().first ?? "Scripts/release/.smoke-bar.png"
guard let img = NSImage(contentsOfFile: capturePath),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff)
else {
    FileHandle.standardError.write(Data("ERROR: smoke capture is missing or invalid: \(capturePath)\n".utf8))
    exit(1)
}
var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
    if let c = rep.colorAt(x: x, y: y), c.redComponent > 0.85, c.blueComponent > 0.85, c.greenComponent < 0.3 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}}
if maxX >= 0 { print("magenta block: \(maxX - minX + 1) x \(maxY - minY + 1) px") } else { print("NOT FOUND") }
