// Renders the 1024×1024 app icon: a stellar core with orbit rings on a deep ember gradient.
// Usage: swift Tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments[1]
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

func render(dark: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Background: diagonal night → ember
    let bg = CGGradient(colorsSpace: cs, colors: dark
        ? [rgb(0.05, 0.02, 0.08), rgb(0.14, 0.03, 0.10), rgb(0.30, 0.06, 0.08)] as CFArray
        : [rgb(0.16, 0.05, 0.22), rgb(0.38, 0.06, 0.18), rgb(0.72, 0.18, 0.10)] as CFArray,
        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

    let c = CGPoint(x: S * 0.5, y: S * 0.5)
    // Outer glow
    let glow = CGGradient(colorsSpace: cs, colors: [rgb(1, 0.62, 0.22, 0.55), rgb(1, 0.45, 0.15, 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: S * 0.46, options: [])

    // Orbit rings (three ellipses rotated 60° apart)
    ctx.setLineWidth(S * 0.022)
    ctx.setLineCap(.round)
    for i in 0..<3 {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(i) * .pi / 3 + .pi / 6)
        ctx.setStrokeColor(rgb(1, 0.86, 0.70, 0.78))
        ctx.strokeEllipse(in: CGRect(x: -S * 0.36, y: -S * 0.13, width: S * 0.72, height: S * 0.26))
        ctx.restoreGState()
    }

    // Core: hot white → amber
    let core = CGGradient(colorsSpace: cs, colors: [rgb(1, 0.99, 0.94), rgb(1, 0.84, 0.45), rgb(1, 0.52, 0.16)] as CFArray, locations: [0, 0.45, 1])!
    let r = S * 0.115
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.clip()
    ctx.drawRadialGradient(core, startCenter: CGPoint(x: c.x - r * 0.3, y: c.y + r * 0.3), startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // A small particle on one orbit
    let p = CGPoint(x: c.x + S * 0.29, y: c.y + S * 0.165)
    let pr = S * 0.034
    ctx.setFillColor(rgb(1, 0.96, 0.88))
    ctx.fillEllipse(in: CGRect(x: p.x - pr, y: p.y - pr, width: 2 * pr, height: 2 * pr))
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
save(render(dark: false), "AppIcon.png")
save(render(dark: true), "AppIcon-Dark.png")
