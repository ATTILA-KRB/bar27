// Génère l'icône de Bar27 (AppIcon.appiconset + docs/logo.png) : `swift scripts/make-icon.swift`.
// Motif : une barre des menus dont les icônes de gauche s'effacent derrière un rideau,
// celles de droite restent nettes ; « 27 » pour macOS 27.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Dessin sur une grille 1024 (gabarit macOS : carré arrondi de 824 centré).
func draw(in ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Ombre portée du carreau.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(color(0x151826).cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Fond : graphite bleuté, plus clair en haut.
    let background = CGGradient(colorsSpace: nil, colors: [color(0x2B3045).cgColor, color(0x0F111A).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Barre des menus.
    let bar = CGRect(x: 100, y: 664, width: 824, height: 132)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor); ctx.fill(bar)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor); ctx.fill(CGRect(x: 100, y: 664, width: 824, height: 3))

    // Icônes : à gauche du rideau elles s'effacent, à droite elles restent nettes.
    // Huit emplacements au même pas, rangée centrée : 4 masquées, le rideau, 3 visibles.
    let pitch: CGFloat = 92, glyph: CGFloat = 62, y = bar.midY - glyph / 2
    let centers = (0..<8).map { 512 + (CGFloat($0) - 3.5) * pitch }
    let curtainX = centers[4]
    for (i, x) in centers.enumerated() where i != 4 {
        let alpha = i < 4 ? 0.20 + 0.10 * CGFloat(i) : 0.95
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - glyph / 2, y: y, width: glyph, height: glyph), cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
    }
    // Rideau : trait ambre qui sépare masqué / visible.
    let amber = CGGradient(colorsSpace: nil, colors: [color(0xFFC46B).cgColor, color(0xFF8A3D).cgColor] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: curtainX - 11, y: bar.minY + 18, width: 22, height: bar.height - 36), cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(amber, start: CGPoint(x: curtainX, y: bar.maxY), end: CGPoint(x: curtainX, y: bar.minY), options: [])
    ctx.restoreGState()

    // « 27 ».
    let font = NSFont.systemFont(ofSize: 380, weight: .heavy)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 380) } ?? font
    let text = NSAttributedString(string: "27", attributes: [.font: rounded, .foregroundColor: NSColor.white, .kern: -8])
    let size = text.size()
    let origin = CGPoint(x: 512 - size.width / 2, y: 175)
    // Remplissage dégradé : on dessine le texte comme masque.
    let line = CTLineCreateWithAttributedString(text)
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: origin.x, y: origin.y + 52)
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(line, ctx)
    let white = CGGradient(colorsSpace: nil, colors: [NSColor.white.cgColor, color(0xC9CFE4).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(white, start: CGPoint(x: 512, y: 600), end: CGPoint(x: 512, y: 200), options: [])
    ctx.restoreGState()

    ctx.restoreGState()
    // Liseré intérieur discret.
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor); ctx.setLineWidth(3); ctx.strokePath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    draw(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let set = root.appending(path: "Bar27/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
var images = [[String: String]]()
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: set.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: set.appending(path: "Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: root.appending(path: "Bar27/Assets.xcassets/Contents.json"))
try png(pixels: 512).write(to: root.appending(path: "docs/logo.png"))
print("Icône : \(set.path), docs/logo.png")
