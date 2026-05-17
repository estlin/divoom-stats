import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Renders a 128x128 RGB888 frame for the Minitoo using a 4-quadrant gauge layout.
///
///   +------+------+
///   | CPU  | GPU  |
///   +------+------+
///   | RAM  | DISK |
///   +------+------+
///
/// Each quadrant: big % number, optional temp below, then a horizontal bar
/// colored by load (green < 60, yellow < 85, red >= 85).
final class FrameRenderer {
    static let side = 128

    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func render(_ s: Stats) -> Data {
        let ctx = CGContext(
            data: nil,
            width: Self.side,
            height: Self.side,
            bitsPerComponent: 8,
            bytesPerRow: Self.side * 4,           // 32-bit BGRA backing, downsample to RGB
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldSmoothFonts(true)

        // Black background.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: Self.side, height: Self.side))

        // Quadrants (CG origin is bottom-left).
        drawQuadrant(ctx, rect: CGRect(x: 0,  y: 64, width: 64, height: 64),
                     label: "CPU", percent: s.cpuPercent,
                     subtext: s.cpuTempC.map { Settings.shared.formatTemp($0) })

        drawQuadrant(ctx, rect: CGRect(x: 64, y: 64, width: 64, height: 64),
                     label: "GPU", percent: s.gpuPercent,
                     subtext: s.gpuTempC.map { Settings.shared.formatTemp($0) })

        drawQuadrant(ctx, rect: CGRect(x: 0,  y: 0, width: 64, height: 64),
                     label: "RAM", percent: s.ramPercent,
                     subtext: String(format: "%.1f/%.0f", s.ramUsedGB, s.ramTotalGB))

        drawQuadrant(ctx, rect: CGRect(x: 64, y: 0, width: 64, height: 64),
                     label: "DISK", percent: s.diskPercent,
                     subtext: String(format: "%.0f/%.0f", s.diskUsedGB, s.diskTotalGB))

        // Subtle 1px divider lines between quadrants.
        ctx.setFillColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 63.5, width: 128, height: 1))
        ctx.fill(CGRect(x: 63.5, y: 0, width: 1, height: 128))

        return packRGB888(from: ctx)
    }

    // MARK: - drawing

    private func drawQuadrant(
        _ ctx: CGContext,
        rect: CGRect,
        label: String,
        percent: Double,
        subtext: String?
    ) {
        let clamped = max(0.0, min(100.0, percent))
        let color = loadColor(clamped)

        // Top: label (e.g. "CPU"), 9pt
        drawText(ctx, label, at: CGPoint(x: rect.minX + 4, y: rect.maxY - 12), size: 9,
                 color: CGColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1), bold: true)

        // Big percentage, 22pt — right-aligned within quadrant
        let pctStr = "\(Int(clamped.rounded()))%"
        drawText(ctx, pctStr,
                 at: CGPoint(x: rect.maxX - 4, y: rect.maxY - 32),
                 size: 22, color: color, bold: true, rightAlign: true)

        // Subtext (temp or used/total), 8pt
        if let sub = subtext {
            drawText(ctx, sub,
                     at: CGPoint(x: rect.minX + 4, y: rect.minY + 12),
                     size: 8, color: CGColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1))
        }

        // Bottom bar — 4px tall, full width minus 4px padding
        let barRect = CGRect(x: rect.minX + 4, y: rect.minY + 4, width: rect.width - 8, height: 4)
        ctx.setFillColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        ctx.fill(barRect)
        let fillW = barRect.width * CGFloat(clamped / 100.0)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: barRect.minX, y: barRect.minY, width: fillW, height: barRect.height))
    }

    private func loadColor(_ pct: Double) -> CGColor {
        if pct >= 85 { return CGColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1) }
        if pct >= 60 { return CGColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1) }
        return CGColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 1)
    }

    private func drawText(
        _ ctx: CGContext,
        _ str: String,
        at point: CGPoint,
        size: CGFloat,
        color: CGColor,
        bold: Bool = false,
        rightAlign: Bool = false
    ) {
        let font = CTFontCreateWithName(
            bold ? "Menlo-Bold" as CFString : "Menlo" as CFString,
            size,
            nil
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attr = NSAttributedString(string: str, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)

        var origin = point
        if rightAlign {
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            origin.x -= CGFloat(w)
        }
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }

    /// Strip alpha and pack as tightly-packed RGB888 (49152 bytes for 128x128).
    private func packRGB888(from ctx: CGContext) -> Data {
        guard let data = ctx.data else { return Data() }
        let src = data.bindMemory(to: UInt8.self, capacity: Self.side * Self.side * 4)
        var out = Data(count: Self.side * Self.side * 3)
        out.withUnsafeMutableBytes { rawDst in
            let dst = rawDst.baseAddress!.assumingMemoryBound(to: UInt8.self)
            // CGBitmapContext memory layout already puts the visual top of what
            // we drew at memory row 0 (Y-up coords mean high CG-Y maps to low
            // row indices). The device interprets row 0 as top, so copy
            // row-for-row without flipping.
            for y in 0..<Self.side {
                let srcRow = y * Self.side * 4
                let dstRow = y * Self.side * 3
                for x in 0..<Self.side {
                    // premultipliedLast = RGBA in memory order
                    dst[dstRow + x*3 + 0] = src[srcRow + x*4 + 0]
                    dst[dstRow + x*3 + 1] = src[srcRow + x*4 + 1]
                    dst[dstRow + x*3 + 2] = src[srcRow + x*4 + 2]
                }
            }
        }
        return out
    }
}
