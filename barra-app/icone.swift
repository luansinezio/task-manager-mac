// Gera AppIcon.icns: quadrado chumbo com o símbolo de checklist em cinza claro.
// Rodar: swift icone.swift  (só precisa se quiser mudar o ícone)
import Cocoa

func png(_ lado: Int) -> Data {
    let s = CGFloat(lado)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        let m = s * 0.1, r = NSRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
        NSColor(white: 0x1A / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225).fill()
        NSColor(white: 0x33 / 255, alpha: 1).setStroke()
        let borda = NSBezierPath(roundedRect: r.insetBy(dx: s * 0.002, dy: s * 0.002), xRadius: r.width * 0.225, yRadius: r.width * 0.225)
        borda.lineWidth = max(1, s * 0.004); borda.stroke()
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
            .applying(.init(paletteColors: [NSColor(white: 0xE8 / 255, alpha: 1)]))
        if let sim = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let t = sim.size
            sim.draw(in: NSRect(x: (s - t.width) / 2, y: (s - t.height) / 2, width: t.width, height: t.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for b in [16, 32, 128, 256, 512] {
    try! png(b).write(to: dir.appendingPathComponent("icon_\(b)x\(b).png"))
    try! png(b * 2).write(to: dir.appendingPathComponent("icon_\(b)x\(b)@2x.png"))
}
