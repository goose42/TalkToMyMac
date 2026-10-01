// Renders the 1024×1024 master app icon to the path given as the first argument.
//
//     swift scripts/generate-icon.swift Resources/AppIcon.png
//
// The output PNG is committed; `make build` turns it into AppIcon.icns. Re-run this only
// when changing the design (or replace the PNG with hand-made artwork of the same size).

import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
let canvas: CGFloat = 1024

// Apple's macOS icon grid: an 824pt rounded rect centred on the 1024 canvas, leaving room
// for the drop shadow that Finder and the Dock expect.
let tileInset: CGFloat = 100
let tileRect = NSRect(x: tileInset, y: tileInset, width: canvas - 2 * tileInset, height: canvas - 2 * tileInset)
let cornerRadius: CGFloat = 185

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not allocate bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Soft shadow under the tile.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.black.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()

// Background gradient, top to bottom.
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.36, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.16, green: 0.47, blue: 0.95, alpha: 1),
])!
gradient.draw(in: tile, angle: -90)

// Waveform glyph, centred.
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig)
else { fatalError("SF Symbol 'waveform' unavailable") }

let symbolSize = symbol.size
symbol.draw(in: NSRect(
    x: (canvas - symbolSize.width) / 2,
    y: (canvas - symbolSize.height) / 2,
    width: symbolSize.width,
    height: symbolSize.height
))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url)
print("Wrote \(outputPath)")
