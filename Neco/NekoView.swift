import AppKit

/// Expands the public-domain oneko XBM bitmaps (see Sprites.swift) into images and
/// caches them. Ink pixels become black, body pixels white, everything else clear.
@MainActor
enum SpriteCache {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let img = cache[name] { return img }
        guard let bits = Sprites.image[name], let mask = Sprites.mask[name] else { return nil }
        let w = Sprites.width, h = Sprites.height, rowBytes = w / 8

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
        ), let px = rep.bitmapData else { return nil }

        for y in 0..<h {
            for x in 0..<w {
                let i = y * rowBytes + x / 8
                let b = Int(x % 8)
                let ink = (bits[i] >> b) & 1
                let opaque = (mask[i] >> b) & 1
                let o = (y * w + x) * 4
                if opaque == 1 {
                    let v: UInt8 = ink == 1 ? 0 : 255 // ink black over a white body
                    px[o] = v; px[o + 1] = v; px[o + 2] = v; px[o + 3] = 255
                } else {
                    px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0
                }
            }
        }

        let img = NSImage(size: NSSize(width: w, height: h))
        img.addRepresentation(rep)
        cache[name] = img
        return img
    }
}

@MainActor
final class NekoView: NSView {
    var neko: Neko?
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let neko = neko, let img = SpriteCache.image(neko.frame) else { return }
        NSGraphicsContext.current?.imageInterpolation = .none // keep hard pixel edges
        img.draw(in: bounds)
    }
}
