// Renders Pumpkin's icon artwork.
//
//   swift scripts/make_icon.swift <output-dir>
//
// Produces:
//   AppIcon.icon/            Icon Composer document (layered, Liquid Glass on macOS 26+)
//   AppIcon.icns             Flat fallback for macOS 14–15
//   AppIcon-1024.png         Flat preview
import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let fm = FileManager.default

let top = CGColor(srgbRed: 0.18, green: 0.32, blue: 0.25, alpha: 1)
let bottom = CGColor(srgbRed: 0.07, green: 0.18, blue: 0.13, alpha: 1)

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Top-left origin, like a design tool.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// The pumpkin-and-countdown glyph, drawn into a square of side `side` centred at `c`.
/// Coordinates are expressed for a 1024 canvas and scaled.
func drawGlyph(_ ctx: CGContext, center c: CGPoint, scale s: CGFloat, color: CGColor, trackAlpha: CGFloat) {
    let radius: CGFloat = 292 * s
    let width: CGFloat = 76 * s

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(width)

    // Track: the time already used up.
    ctx.setStrokeColor(color.copy(alpha: trackAlpha)!)
    ctx.addArc(center: c, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Remaining time: three quarters, from 12 o'clock clockwise (y points down).
    ctx.setStrokeColor(color)
    ctx.addArc(center: c, radius: radius, startAngle: -.pi / 2, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // A friendly pumpkin inside the countdown ring.
    let pumpkin = CGColor(srgbRed: 1, green: 0.48, blue: 0.12, alpha: 1)
    ctx.setFillColor(pumpkin)
    for dx in [-70.0, 0.0, 70.0] {
        ctx.fillEllipse(in: CGRect(x: c.x + CGFloat(dx) * s - 94 * s, y: c.y - 104 * s, width: 188 * s, height: 238 * s))
    }
    ctx.setStrokeColor(CGColor(srgbRed: 0.94, green: 0.34, blue: 0.08, alpha: 1))
    ctx.setLineWidth(10 * s)
    for dx in [-38.0, 38.0] {
        ctx.addEllipse(in: CGRect(x: c.x + CGFloat(dx) * s - 42 * s, y: c.y - 92 * s, width: 84 * s, height: 218 * s))
        ctx.strokePath()
    }
    ctx.setStrokeColor(color)
    ctx.setLineWidth(28 * s)
    ctx.move(to: CGPoint(x: c.x, y: c.y - 104 * s))
    ctx.addQuadCurve(to: CGPoint(x: c.x + 29 * s, y: c.y - 172 * s), control: CGPoint(x: c.x - 12 * s, y: c.y - 148 * s))
    ctx.strokePath()
    let ink = CGColor(srgbRed: 0.07, green: 0.18, blue: 0.13, alpha: 1)
    ctx.setFillColor(ink)
    for dx in [-52.0, 52.0] {
        ctx.fillEllipse(in: CGRect(x: c.x + CGFloat(dx) * s - 10 * s, y: c.y - 5 * s, width: 20 * s, height: 26 * s))
    }
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(12 * s)
    ctx.move(to: CGPoint(x: c.x - 36 * s, y: c.y + 45 * s))
    ctx.addQuadCurve(to: CGPoint(x: c.x + 36 * s, y: c.y + 45 * s), control: CGPoint(x: c.x, y: c.y + 88 * s))
    ctx.strokePath()
    ctx.restoreGState()
}

/// macOS-style squircle (superellipse, n = 5).
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

// MARK: - Icon Composer document

let iconDoc = outDir.appendingPathComponent("AppIcon.icon", isDirectory: true)
try? fm.removeItem(at: iconDoc)
try! fm.createDirectory(at: iconDoc.appendingPathComponent("Assets"), withIntermediateDirectories: true)

do {
    let ctx = makeContext(1024)
    drawGlyph(ctx, center: CGPoint(x: 512, y: 512), scale: 1, color: CGColor(gray: 1, alpha: 1), trackAlpha: 0.38)
    writePNG(ctx, to: iconDoc.appendingPathComponent("Assets/glyph.png"))
}

let iconJSON = """
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.18000,0.32000,0.25000,1.00000",
      "srgb:0.07000,0.18000,0.13000,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "glyph.png",
          "name" : "glyph"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}
"""
try! iconJSON.write(to: iconDoc.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)

// MARK: - Flat icon (Big Sur grid: 824pt shape inside a 1024pt canvas)

func renderFlat(_ size: Int) -> CGContext {
    let ctx = makeContext(size)
    let k = CGFloat(size) / 1024
    let shape = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = squirclePath(in: shape)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(path)
    ctx.setFillColor(bottom)
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient body.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: shape.minY), end: CGPoint(x: 0, y: shape.maxY), options: [])

    // Soft sheen across the top.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: shape.midX, y: shape.minY), startRadius: 0, endCenter: CGPoint(x: shape.midX, y: shape.minY), endRadius: 560 * k, options: [])

    // Glyph with a gentle lift.
    ctx.setShadow(offset: CGSize(width: 0, height: 8 * k), blur: 18 * k, color: CGColor(srgbRed: 0.55, green: 0.12, blue: 0.05, alpha: 0.35))
    drawGlyph(ctx, center: CGPoint(x: shape.midX, y: shape.midY), scale: 0.824 * k, color: CGColor(gray: 1, alpha: 1), trackAlpha: 0.38)
    ctx.restoreGState()

    // Hairline edge.
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(2 * k)
    ctx.strokePath()
    return ctx
}

writePNG(renderFlat(1024), to: outDir.appendingPathComponent("AppIcon-1024.png"))

let iconset = fm.temporaryDirectory.appendingPathComponent("Pumpkin-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(renderFlat(base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(renderFlat(base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Icons written to \(outDir.path)" : "iconutil failed")
