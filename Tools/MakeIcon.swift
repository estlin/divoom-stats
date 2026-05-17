#!/usr/bin/env swift
// Generates AppIcon.iconset (+ optional .icns) for Divoom Stats.
//
// Usage:   swift Tools/MakeIcon.swift [output-iconset-dir]
// Default: AppIcon.iconset in the current directory.
//
// Aesthetic: rounded black square with four colored quadrant gauges,
// echoing the on-device 4-quadrant layout the app draws.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Each (filename, pixel-size) entry required for a macOS .iconset.
let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeIcon(size: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let S = CGFloat(size)
    // Rounded-rect background that follows macOS's "squircle-ish" radius (≈22.4% of side).
    let radius = S * 0.224
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    ctx.fillPath()

    // Inner inset so quadrants sit inside the rounded edge.
    let inset = S * 0.10
    let inner = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)

    // Subtle quadrant dividers.
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1))
    ctx.setLineWidth(max(1, S/128))
    ctx.move(to: CGPoint(x: inner.minX, y: inner.midY))
    ctx.addLine(to: CGPoint(x: inner.maxX, y: inner.midY))
    ctx.move(to: CGPoint(x: inner.midX, y: inner.minY))
    ctx.addLine(to: CGPoint(x: inner.midX, y: inner.maxY))
    ctx.strokePath()

    // Four quadrant gauges. Loads chosen to look balanced/lively.
    let quads: [(rect: CGRect, fill: CGFloat, color: CGColor)] = [
        // top-left  (CG origin is bottom-left, so top = high Y)
        (CGRect(x: inner.minX, y: inner.midY, width: inner.width/2, height: inner.height/2),
         0.62, CGColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1)),     // CPU — yellow
        // top-right
        (CGRect(x: inner.midX, y: inner.midY, width: inner.width/2, height: inner.height/2),
         0.18, CGColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 1)),     // GPU — green
        // bottom-left
        (CGRect(x: inner.minX, y: inner.minY, width: inner.width/2, height: inner.height/2),
         0.88, CGColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)),     // RAM — red
        // bottom-right
        (CGRect(x: inner.midX, y: inner.minY, width: inner.width/2, height: inner.height/2),
         0.42, CGColor(red: 0.30, green: 0.65, blue: 0.95, alpha: 1)),     // DISK — blue
    ]

    let padding = S * 0.025
    for (rect, fill, color) in quads {
        // Big colored "bar" that fills `fill` fraction of the quadrant height from the bottom.
        let barRect = rect.insetBy(dx: padding, dy: padding)
        // background track (faint).
        ctx.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1))
        ctx.fill(barRect)
        // filled portion.
        let filledHeight = barRect.height * fill
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: barRect.minX, y: barRect.minY,
                        width: barRect.width, height: filledHeight))
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "MakeIcon", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "MakeIcon", code: 2) }
}

for entry in entries {
    let img = makeIcon(size: entry.size)
    let path = "\(outDir)/\(entry.name)"
    try writePNG(img, to: path)
    print("wrote \(path) (\(entry.size)x\(entry.size))")
}

print("Done. Convert with: iconutil -c icns \(outDir)")
