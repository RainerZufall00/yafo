// Erzeugt das App-Icon „G3 · Familie vor dem Y“ für App/Resources/Assets.xcassets/AppIcon.appiconset.
//
//     swift Tools/AppIcon/build.swift                      # helle, dunkle und getönte Variante schreiben
//     swift Tools/AppIcon/build.swift --preview /tmp/i.html   # zusätzlich Vorschauseite
//
// Keine Abhängigkeiten außer CoreGraphics. Raster 1024 × 1024, Koordinaten wie SVG (y nach unten);
// die Entwürfe liegen in Tools/AppIcon/concepts/ (G3 = g3-y-familie-hand.svg).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let here = URL(fileURLWithPath: #filePath,
               relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    .absoluteURL.deletingLastPathComponent()
let output = here.appendingPathComponent("../../App/Resources/Assets.xcassets/AppIcon.appiconset").standardized

// MARK: - Farben

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

struct Palette {
    /// Verlauf oben → unten; nil = transparenter Grund (dunkel/getönt, das System legt den Hintergrund).
    var background: (CGColor, CGColor)?
    var y: CGColor
    var parents: CGColor
    var child: CGColor
}

let variants: [(file: String, appearance: String?, palette: Palette)] = [
    ("AppIcon.png", nil, Palette(background: (rgb(0x38B17A), rgb(0x1D7A4F)),
                                 y: gray(1, 0.22), parents: gray(1), child: rgb(0xFFD84D))),
    ("AppIcon-dark.png", "dark", Palette(background: nil,
                                         y: rgb(0x38B17A, 0.45), parents: rgb(0x5FD39C), child: rgb(0xFFD84D))),
    ("AppIcon-tinted.png", "tinted", Palette(background: nil,
                                             y: gray(1, 0.3), parents: gray(1), child: gray(0.72))),
]

// MARK: - Formen

/// Figur aus Kopf und Körper; `grow` vergrößert (positiv) oder verkleinert (negativ) beide Teile.
func figure(cx: CGFloat, headY: CGFloat, headR: CGFloat, bodyTop: CGFloat, bodyW: CGFloat, bodyH: CGFloat,
            grow: CGFloat = 0) -> CGPath {
    let path = CGMutablePath()
    let r = headR + grow
    path.addEllipse(in: CGRect(x: cx - r, y: headY - r, width: 2 * r, height: 2 * r))
    let body = CGRect(x: cx - bodyW / 2, y: bodyTop, width: bodyW, height: bodyH).insetBy(dx: -grow, dy: -grow)
    let corner = bodyW / 2 + grow
    path.addRoundedRect(in: body, cornerWidth: corner, cornerHeight: corner)
    return path
}

func parent(_ cx: CGFloat) -> CGPath {
    figure(cx: cx, headY: 470, headR: 70, bodyTop: 560, bodyW: 160, bodyH: 300)
}

func child(grow: CGFloat) -> CGPath {
    figure(cx: 512, headY: 600, headR: 58, bodyTop: 672, bodyW: 140, bodyH: 210, grow: grow)
}

/// Das große Y als Bühne hinter der Familie.
func letterY() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 512, y: 880))
    path.addLine(to: CGPoint(x: 512, y: 600))
    path.move(to: CGPoint(x: 512, y: 600))
    path.addLine(to: CGPoint(x: 330, y: 330))
    path.move(to: CGPoint(x: 512, y: 600))
    path.addLine(to: CGPoint(x: 694, y: 330))
    return path.copy(strokingWithWidth: 150, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// MARK: - Zeichnen

func render(_ palette: Palette) -> CGImage {
    let opaque = palette.background != nil
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                                               : CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)

    func fillBackground() {
        guard let (top, bottom) = palette.background else { return }
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    func fill(_ path: CGPath, _ color: CGColor) {
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
    }

    fillBackground()
    fill(letterY(), palette.y)
    fill(parent(330), palette.parents)
    fill(parent(694), palette.parents)

    // Lücke um das Kind: auf farbigem Grund mit dem Hintergrund übermalt, sonst ausgestanzt.
    context.saveGState()
    context.addPath(child(grow: 11))
    context.clip()
    if opaque {
        fillBackground()
    } else {
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    }
    context.restoreGState()
    fill(child(grow: -11), palette.child)

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "konnte \(url.path) nicht schreiben")
}

// MARK: - Ausgabe

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: Any]] = []
for variant in variants {
    writePNG(render(variant.palette), to: output.appendingPathComponent(variant.file))
    var entry: [String: Any] = ["filename": variant.file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance = variant.appearance {
        entry["appearances"] = [["appearance": "luminosity", "value": appearance]]
    }
    images.append(entry)
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try (String(decoding: json, as: UTF8.self) + "\n").write(to: output.appendingPathComponent("Contents.json"),
                                                         atomically: true, encoding: .utf8)
print("\(variants.count) Varianten → \(output.path)")

// MARK: - Vorschau

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
    let previewURL = URL(fileURLWithPath: arguments[index + 1])
    let base = output.absoluteString
    func tile(_ file: String, _ points: Int, _ ground: String) -> String {
        "<img src=\"\(base)\(file)\" width=\"\(points)\" height=\"\(points)\" style=\"background:\(ground)\">"
    }
    var rows = ""
    for (file, label, ground, wall) in [
        ("AppIcon.png", "Hell", "transparent", "linear-gradient(135deg,#cfe3ff,#ffe1d2)"),
        ("AppIcon-dark.png", "Dunkel", "linear-gradient(#2c2c2e,#0c0c0d)", "linear-gradient(135deg,#1b2238,#3a1f2a)"),
        ("AppIcon-tinted.png", "Getönt (ohne Tönung)", "linear-gradient(#2c2c2e,#0c0c0d)", "#111"),
    ] {
        let small = [180, 60, 40, 29, 20].map { tile(file, $0, ground) }.joined()
        rows += "<section><h2>\(label)</h2><div class=\"wall\" style=\"background:\(wall)\">\(small)</div></section>\n"
    }
    let html = """
    <!doctype html><html lang="de"><head><meta charset="utf-8"><title>yafo App-Icon</title><style>
    body{margin:0;padding:24px;background:#f2f2f7;font:15px -apple-system,system-ui,sans-serif}
    h2{font-size:15px;margin:16px 0 8px}.wall{display:flex;align-items:center;gap:16px;padding:20px;border-radius:16px}
    img{border-radius:22.37%;display:block}
    </style></head><body><h1>yafo · G3 Familie vor dem Y</h1>
    \(rows)</body></html>
    """
    try html.write(to: previewURL, atomically: true, encoding: .utf8)
    print("Vorschau → \(previewURL.path)")
}
