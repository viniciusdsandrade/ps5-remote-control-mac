// Draws the "Controle PS5" app icon in vector form (CoreGraphics), a white DualSense seen from above, and
// writes the .iconset. Usage: swift make_icon.swift <out.iconset>  →  iconutil -c icns <out.iconset> -o AppIcon.icns
// For the iPhone: swift make_icon.swift --ios <out.png> writes the 1024×1024 opaque tile.
// Design coordinates: a 1024×1024 canvas with the origin at the top left. Only the controller is drawn, with no
// tile behind it, like the icon of "Controle Remoto LG"; scripts/build_app.sh applies it as a custom icon, which
// macOS 26 shows as is instead of putting it inside a grey frame.
import CoreGraphics
import Foundation
import ImageIO

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255,
                                           CGFloat(v & 0xFF) / 255, a])!
}
func white(_ a: CGFloat) -> CGColor { CGColor(colorSpace: sRGB, components: [1, 1, 1, a])! }
func black(_ a: CGFloat) -> CGColor { CGColor(colorSpace: sRGB, components: [0, 0, 0, a])! }
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Shapes

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

func pill(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, angle: CGFloat = 0) -> CGPath {
    let r = min(w, h) / 2
    var t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
    return CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: r, cornerHeight: r,
                  transform: &t)
}

/// Polygon with every corner rounded to `radius`.
func roundedPolygon(_ points: [CGPoint], _ radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = points.count
    p.move(to: pt((points[n - 1].x + points[0].x) / 2, (points[n - 1].y + points[0].y) / 2))
    for i in 0..<n { p.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: radius) }
    p.closeSubpath()
    return p
}

/// Left-right symmetric outline. `half` holds the cubic segments (control 1, control 2, end) of the right half,
/// from `start` on the axis down to a point on the axis; the left half is its mirror image, traced back up.
func symmetric(_ start: CGPoint, _ half: [(CGPoint, CGPoint, CGPoint)]) -> CGPath {
    let mirror = { (q: CGPoint) in pt(1024 - q.x, q.y) }
    let ends = [start] + half.map { $0.2 }
    let p = CGMutablePath()
    p.move(to: start)
    for (c1, c2, end) in half { p.addCurve(to: end, control1: c1, control2: c2) }
    for i in stride(from: half.count - 1, through: 0, by: -1) {
        p.addCurve(to: mirror(ends[i]), control1: mirror(half[i].1), control2: mirror(half[i].0))
    }
    p.closeSubpath()
    return p
}

// MARK: - Painting

struct Painter {
    let ctx: CGContext
    let k: CGFloat        // pixels per design unit
    let detail: Int       // 0: 16–32 px, 1: 64 px, 2: 128 px or more

    /// Line width that never gets thinner than `minPx` real pixels.
    func w(_ units: CGFloat, minPx: CGFloat) -> CGFloat { max(units, minPx / k) }

    func shadowed(dy: CGFloat, blur: CGFloat, color: CGColor, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * k), blur: blur * k, color: color)
        draw()
        ctx.restoreGState()
    }
    func clipped(to p: CGPath, _ draw: () -> Void) {
        ctx.saveGState(); ctx.addPath(p); ctx.clip(); draw(); ctx.restoreGState()
    }
    func fill(_ p: CGPath, _ c: CGColor) {
        ctx.addPath(p); ctx.setFillColor(c); ctx.fillPath()
    }
    func fill(_ p: CGPath, _ g: CGGradient, _ y0: CGFloat, _ y1: CGFloat) {
        clipped(to: p) {
            ctx.drawLinearGradient(g, start: pt(0, y0), end: pt(0, y1),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
    func fillRadial(_ p: CGPath, _ g: CGGradient, _ center: CGPoint, _ radius: CGFloat) {
        clipped(to: p) {
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                                   options: [.drawsAfterEndLocation])
        }
    }
    func stroke(_ p: CGPath, _ width: CGFloat, _ g: CGGradient, _ y0: CGFloat, _ y1: CGFloat) {
        ctx.saveGState(); ctx.addPath(p); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(g, start: pt(0, y0), end: pt(0, y1),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    func stroke(_ p: CGPath, _ width: CGFloat, _ c: CGColor) {
        ctx.saveGState(); ctx.addPath(p); ctx.setLineWidth(width); ctx.setStrokeColor(c)
        ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath(); ctx.restoreGState()
    }
    /// Inner outline: a stroke clipped by its own path, so only the inner half shows.
    func innerStroke(_ p: CGPath, _ width: CGFloat, _ g: CGGradient, _ y0: CGFloat, _ y1: CGFloat) {
        clipped(to: p) { stroke(p, width * 2, g, y0, y1) }
    }
}

/// Slightly raised dark key: short shadow, vertical gradient and a light rim on top.
func key(_ P: Painter, _ path: CGPath, _ y0: CGFloat, _ y1: CGFloat, top: UInt32 = 0x34373D, bottom: UInt32 = 0x1A1C20) {
    P.shadowed(dy: 3, blur: 6, color: black(0.55)) { P.fill(path, hex(bottom)) }
    P.fill(path, grad([(0, hex(top)), (1, hex(bottom))]), y0, y1)
    if P.detail > 1 {
        P.innerStroke(path, P.w(2, minPx: 0.6), grad([(0, white(0.22)), (0.5, white(0))]), y0, y1)
    }
}

// MARK: - Controller

// The colours of the symbols on the app's pad (PadTheme).
let triangleColor = hex(0x4DCC8C), circleColor = hex(0xF56B6B), crossColor = hex(0x7AA8F7), squareColor = hex(0xF285BD)
let lightBar = hex(0x3D8BFF)

func drawController(_ P: Painter, scale: CGFloat = 0.92) {
    // 92% of the canvas on the Mac, centred: the margin keeps it the same visual size as its neighbours in the
    // Dock. On iOS the controller sits on a tile and gets more room around it.
    P.ctx.translateBy(x: 512, y: 512)
    P.ctx.scaleBy(x: scale, y: scale)
    P.ctx.translateBy(x: -512, y: -538)

    // Outline, right half: top edge rising a little towards R1, shoulder, outer side, grip down to its round tip,
    // inner side of the grip and the bottom edge between the grips.
    let shell = symmetric(pt(512, 226), [
        (pt(610, 226), pt(706, 216), pt(790, 220)),
        (pt(884, 224), pt(940, 254), pt(958, 322)),
        (pt(972, 380), pt(980, 452), pt(984, 532)),
        (pt(990, 640), pt(992, 752), pt(944, 812)),
        (pt(904, 860), pt(822, 862), pt(792, 806)),
        (pt(764, 752), pt(738, 676), pt(668, 640)),
        (pt(612, 612), pt(560, 606), pt(512, 606)),
    ])
    let top: CGFloat = 216, bottom: CGFloat = 860

    // White shell with a soft drop shadow, lit from the top left.
    P.shadowed(dy: 14, blur: 30, color: black(0.45)) { P.fill(shell, hex(0xE9ECF0)) }
    P.fill(shell, grad([(0, hex(0xFFFFFF)), (0.5, hex(0xF2F4F7)), (1, hex(0xD5DAE1))]), top, bottom)
    P.fillRadial(shell, grad([(0, white(0.75)), (1, white(0))]), pt(360, 260), 420)

    // Black middle: from under the touchpad out to the D-pad and the face buttons and down between the grips.
    // Clipped by the outline, so its lower edge can overshoot.
    let core = symmetric(pt(512, 304), [
        (pt(640, 304), pt(748, 276), pt(824, 284)),
        (pt(902, 292), pt(926, 386), pt(898, 470)),
        (pt(868, 552), pt(782, 618), pt(702, 684)),
        (pt(642, 734), pt(582, 744), pt(512, 744)),
    ])
    P.clipped(to: shell) {
        P.fill(core, grad([(0, hex(0x2B2D32)), (0.6, hex(0x1A1B1F)), (1, hex(0x111215))]), 290, 640)
        P.fillRadial(core, grad([(0, white(0.07)), (1, white(0))]), pt(512, 360), 300)
        P.stroke(core, P.w(3, minPx: 0.5), hex(0x0B0C0E, 0.7))
    }

    // Rim: light on the upper edge, a touch of shade below, and a fine grey line so the white body keeps its
    // shape on a light Dock.
    if P.detail > 0 {
        P.innerStroke(shell, P.w(3, minPx: 0.8),
                      grad([(0, white(0.95)), (0.35, white(0.2)), (0.7, black(0.06)), (1, black(0.14))]), top, bottom)
    }
    P.stroke(shell, P.w(2, minPx: 0.7), hex(0x8E95A0, 0.75))

    // Touchpad, with the light bar glowing along both sides.
    let touchpad = roundedPolygon([pt(356, 240), pt(668, 240), pt(652, 414), pt(372, 414)], 28)
    P.shadowed(dy: 2, blur: 5, color: black(0.18)) { P.fill(touchpad, hex(0xF4F6F8)) }
    P.fill(touchpad, grad([(0, hex(0xFDFDFE)), (1, hex(0xE6E9EE))]), 240, 414)
    P.innerStroke(touchpad, P.w(2.5, minPx: 0.6), grad([(0, black(0.04)), (1, black(0.16))]), 240, 414)
    if P.detail > 0 {
        for side: CGFloat in [-1, 1] {
            let bar = CGMutablePath()
            bar.move(to: pt(512 + side * 168, 270))
            bar.addQuadCurve(to: pt(512 + side * 148, 412), control: pt(512 + side * 164, 380))
            P.shadowed(dy: 0, blur: 28, color: hex(0x3D8BFF)) { P.stroke(bar, P.w(9, minPx: 1.2), lightBar) }
            if P.detail > 1 { P.stroke(bar, 3, hex(0xBFD8FF)) }
        }
    }

    // Create and Options, beside the top corners of the touchpad.
    if P.detail > 1 {
        for side: CGFloat in [-1, 1] {
            key(P, pill(512 + side * 204, 262, 15, 36, angle: side * 0.42), 244, 280, top: 0x4A4D54, bottom: 0x2A2C31)
        }
    }

    // D-pad: four arrow-shaped keys with a pointed inner end.
    let dpad = pt(228, 400)
    if P.detail > 0 {
        let up = [pt(-26, -92), pt(26, -92), pt(26, -44), pt(0, -18), pt(-26, -44)]
        for quarter in 0..<4 {
            let a = CGFloat(quarter) * .pi / 2
            let turn = { (q: CGPoint) in pt(dpad.x + q.x * cos(a) - q.y * sin(a), dpad.y + q.x * sin(a) + q.y * cos(a)) }
            key(P, roundedPolygon(up.map(turn), 9), dpad.y - 92, dpad.y + 92)
            if P.detail > 1 {
                let arrow = roundedPolygon([pt(0, -76), pt(11, -60), pt(-11, -60)].map(turn), 2)
                P.fill(arrow, hex(0x8D929B))
            }
        }
    }

    // Face buttons: △ ○ ✕ □ in the colours of the app.
    let face = pt(796, 400)
    if P.detail > 1 {
        let spots: [(CGFloat, CGFloat)] = [(0, -64), (64, 0), (0, 64), (-64, 0)]
        for (dx, dy) in spots {
            key(P, circle(face.x + dx, face.y + dy, 33), face.y + dy - 33, face.y + dy + 33,
                top: 0x2F3238, bottom: 0x17191C)
        }
        let lw: CGFloat = 6.5
        let t = roundedPolygon([pt(face.x, face.y - 82), pt(face.x + 16, face.y - 54), pt(face.x - 16, face.y - 54)], 2)
        P.stroke(t, lw, triangleColor)
        P.stroke(circle(face.x + 64, face.y, 15), lw, circleColor)
        let x = CGMutablePath()
        x.move(to: pt(face.x - 13, face.y + 51)); x.addLine(to: pt(face.x + 13, face.y + 77))
        x.move(to: pt(face.x + 13, face.y + 51)); x.addLine(to: pt(face.x - 13, face.y + 77))
        P.stroke(x, lw, crossColor)
        P.stroke(CGPath(rect: CGRect(x: face.x - 78, y: face.y - 14, width: 28, height: 28), transform: nil), lw,
                 squareColor)
    } else if P.detail > 0 {
        let spots: [(CGFloat, CGFloat, CGColor)] = [(0, -64, triangleColor), (64, 0, circleColor),
                                                    (0, 64, crossColor), (-64, 0, squareColor)]
        for (dx, dy, color) in spots { P.fill(circle(face.x + dx, face.y + dy, 26), color) }
    }

    // Sticks: a dark well, a concave cap and a light edge on top.
    for cx: CGFloat in [352, 672] {
        let cy: CGFloat = 540
        P.fill(circle(cx, cy, 74), hex(0x0C0D0F))
        let cap = circle(cx, cy, 58)
        P.shadowed(dy: 4, blur: 8, color: black(0.6)) { P.fill(cap, hex(0x1D1F23)) }
        P.fillRadial(cap, grad([(0, hex(0x17181B)), (0.62, hex(0x24262B)), (0.85, hex(0x383B42)), (1, hex(0x2A2C31))]),
                     pt(cx, cy), 58)
        if P.detail > 0 {
            P.innerStroke(cap, P.w(2.5, minPx: 0.6), grad([(0, white(0.28)), (0.5, white(0))]), cy - 58, cy + 58)
        }
        if P.detail > 1 {
            P.stroke(circle(cx, cy, 40), 2, black(0.45))
        }
    }

    // PS button and the microphone key under it.
    if P.detail > 0 {
        key(P, circle(512, 538, 23), 515, 561, top: 0x2E3035, bottom: 0x0F1012)
    }
    if P.detail > 1 {
        key(P, pill(512, 580, 46, 13), 573, 587, top: 0x3A3D43, bottom: 0x1E2024)
    }
}

/// iOS tile: iOS wants an opaque square and rounds the corners itself. Deep graphite blue with a soft light from
/// the top, so the white controller stands out and the light bar picks up the blue.
func drawTile(_ P: Painter) {
    let tile = CGPath(rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), transform: nil)
    P.fill(tile, grad([(0, hex(0x2A3556)), (0.55, hex(0x182036)), (1, hex(0x0C101C))]), 0, 1024)
    P.fillRadial(tile, grad([(0, hex(0x5B78C8, 0.55)), (1, hex(0x5B78C8, 0))]), pt(512, 260), 760)
}

// MARK: - Output

func render(_ size: Int, tile: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: (tile ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    let k = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: k, y: -k)
    let painter = Painter(ctx: ctx, k: k, detail: size >= 128 ? 2 : (size >= 64 ? 1 : 0))
    if tile {
        drawTile(painter)
        drawController(painter, scale: 0.78)
    } else {
        drawController(painter)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

// Usage for iOS: swift make_icon.swift --ios <out.png>  (1024×1024, opaque)
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--ios" {
    writePNG(render(1024, tile: true), CommandLine.arguments[2])
    print("ícone do iOS gerado em \(CommandLine.arguments[2])")
    exit(0)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                   ("512x512@2x", 1024)] {
    writePNG(render(px), "\(out)/icon_\(name).png")
}
print("ícone gerado em \(out)")
