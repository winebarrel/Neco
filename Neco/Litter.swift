import AppKit

// The mess the cat leaves behind. Neco drops paw prints while it runs and scratch
// marks while it works its claws (grooming or clawing a wall). Marks live in global
// screen coordinates, fade out over their lifetime, and are drawn by LitterView on a
// full-screen overlay panel that sits just below the cat.

/// One mark on the screen. Kept file-private so LitterField owns the whole lifecycle.
private struct Mark {
    enum Kind { case paw, scratch }
    let kind: Kind
    let pos: NSPoint // global screen coordinates
    let angle: CGFloat // radians: paw points along travel, scratch is tilted
    let birth: Int // tick when created
}

/// Accumulates and ages the cat's marks. `update(neko:)` is called once per 60fps
/// tick; it emits new marks from the cat's motion and culls faded ones, returning the
/// global-coordinate rects that changed so the view can repaint just those, not the
/// whole multi-screen overlay.
@MainActor
final class LitterField {
    var pawsEnabled = false
    var scratchEnabled = false

    /// Half-size of a mark's bounding box, used for partial invalidation and to skip
    /// off-screen marks while drawing. Generous enough to cover any rotated paw/scratch.
    static let markRadius: CGFloat = 16

    fileprivate private(set) var marks: [Mark] = []
    private var tick = 0
    private var prevPos: NSPoint?
    private var lastPawPos: NSPoint? // nil until the first running frame seeds it
    private var pawSide: CGFloat = 1 // flip each print for a left/right foot
    private var lastScratch = -9999 // safely in the past; never Int.min (subtraction would overflow)

    // Tunables. Times are in ticks (60 per second).
    private let pawSpacing: CGFloat = 26 // travel distance between paw prints
    private let scratchInterval = 9 // ~7 scratch marks per second while clawing
    private let pawLife = 60 * 12 // 12s
    private let scratchLife = 60 * 20 // 20s
    private let maxMarks = 400 // hard cap: drop the oldest beyond this

    private func life(of kind: Mark.Kind) -> Int {
        kind == .paw ? pawLife : scratchLife
    }

    private func rect(for mark: Mark) -> NSRect {
        let r = Self.markRadius
        return NSRect(x: mark.pos.x - r, y: mark.pos.y - r, width: r * 2, height: r * 2)
    }

    /// Advance one tick. Returns the global rects of marks that appeared or vanished
    /// this tick (added, culled by age, or evicted by the cap) — the caller invalidates
    /// just these. Ongoing fade is refreshed separately via `fadingRects()`.
    func update(neko: Neko) -> [NSRect] {
        tick += 1
        let pos = neko.pos
        defer { prevPos = pos }

        var dirty: [NSRect] = []
        marks.removeAll { mark in
            guard tick - mark.birth > life(of: mark.kind) else { return false }
            dirty.append(rect(for: mark))
            return true
        }

        if pawsEnabled, neko.isRunning {
            if let last = lastPawPos, hypot(pos.x - last.x, pos.y - last.y) >= pawSpacing {
                let heading = prevPos.map { atan2(pos.y - $0.y, pos.x - $0.x) } ?? 0
                // Step sideways from the path so prints alternate like real feet.
                let off = 6 * pawSide
                let p = NSPoint(x: pos.x + cos(heading + .pi / 2) * off,
                                y: pos.y + sin(heading + .pi / 2) * off)
                dirty += add(Mark(kind: .paw, pos: p, angle: heading, birth: tick))
                lastPawPos = pos
                pawSide *= -1
            } else if lastPawPos == nil {
                lastPawPos = pos // seed on the first running frame; the first step drops no print
            }
        } else {
            lastPawPos = pos // measure spacing fresh from where the next run starts
        }

        if scratchEnabled, neko.isClawing, tick - lastScratch >= scratchInterval {
            // Deterministic scatter (no RNG): derive jitter and tilt from the tick.
            let jitter = CGFloat((tick * 37) % 18 - 9)
            let tilt = CGFloat((tick * 53) % 50 - 25) * .pi / 180
            let p = NSPoint(x: pos.x + jitter, y: pos.y + jitter * 0.5)
            dirty += add(Mark(kind: .scratch, pos: p, angle: tilt, birth: tick))
            lastScratch = tick
        }

        return dirty
    }

    /// Append a mark and return the rects to invalidate: the new mark's, plus any
    /// evicted when the cap is exceeded (so their pixels get cleared too).
    private func add(_ mark: Mark) -> [NSRect] {
        marks.append(mark)
        var dirty = [rect(for: mark)]
        if marks.count > maxMarks {
            let overflow = marks.count - maxMarks
            dirty += marks.prefix(overflow).map { rect(for: $0) }
            marks.removeFirst(overflow)
        }
        return dirty
    }

    /// Global rects of marks currently in their fade window; the caller invalidates
    /// these on a throttle so they dim smoothly without full-screen repaints.
    func fadingRects() -> [NSRect] {
        marks.compactMap { mark in
            let fadeStart = Int(Double(life(of: mark.kind)) * 0.75)
            return tick - mark.birth > fadeStart ? rect(for: mark) : nil
        }
    }

    func clear() {
        marks.removeAll()
    }

    /// Opacity for a mark: full for most of its life, then fading over the last quarter.
    fileprivate func alpha(of mark: Mark) -> CGFloat {
        let age = CGFloat(tick - mark.birth)
        let life = CGFloat(life(of: mark.kind))
        let fadeStart = life * 0.75
        guard age > fadeStart else { return 1 }
        return max(0, 1 - (age - fadeStart) / (life - fadeStart))
    }
}

/// Draws every current mark onto the full-screen overlay panel. `originOffset` is the
/// panel's origin in global coordinates, so a global mark maps to a local point by
/// subtracting it.
@MainActor
final class LitterView: NSView {
    var field: LitterField?
    var originOffset = NSPoint.zero

    override var isFlipped: Bool {
        false
    }

    /// Invalidate a global-coordinate rect, mapped into this view's local space, so
    /// only the changed patch repaints instead of the whole overlay.
    func invalidateGlobal(_ globalRect: NSRect) {
        setNeedsDisplay(NSRect(x: globalRect.minX - originOffset.x,
                               y: globalRect.minY - originOffset.y,
                               width: globalRect.width, height: globalRect.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Clear only the invalidated patch (not the full multi-screen bounds), then
        // repaint just the marks that overlap it. AppKit clips drawing to dirtyRect.
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let field, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = LitterField.markRadius
        for mark in field.marks {
            let p = NSPoint(x: mark.pos.x - originOffset.x, y: mark.pos.y - originOffset.y)
            let box = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            guard box.intersects(dirtyRect) else { continue }
            let a = field.alpha(of: mark)
            switch mark.kind {
            case .paw: Self.drawPaw(ctx, at: p, angle: mark.angle, alpha: a)
            case .scratch: Self.drawScratch(ctx, at: p, angle: mark.angle, alpha: a)
            }
        }
    }

    // Base colors cached once; per-mark opacity is applied with ctx.setAlpha so no
    // NSColor/CGColor is allocated per mark per frame.
    private static let pawColor = NSColor(calibratedWhite: 0.12, alpha: 0.5).cgColor
    private static let scratchColor = NSColor(calibratedWhite: 0.1, alpha: 0.45).cgColor

    /// A paw print: one big pad plus four toe beans, drawn pointing +y then rotated
    /// so it points along the direction of travel.
    private static func drawPaw(_ ctx: CGContext, at p: NSPoint, angle: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle - .pi / 2) // shape points +y; align +y with travel
        ctx.setAlpha(alpha) // scales the cached color's alpha (0.5) → 0.5 * alpha
        ctx.setFillColor(pawColor)
        let s: CGFloat = 1.2
        ctx.fillEllipse(in: CGRect(x: -5 * s, y: -6 * s, width: 10 * s, height: 8 * s))
        let toes = [CGPoint(x: -5, y: 3), CGPoint(x: -2, y: 6.5), CGPoint(x: 2, y: 6.5), CGPoint(x: 5, y: 3)]
        for t in toes {
            ctx.fillEllipse(in: CGRect(x: (t.x - 1.6) * s, y: (t.y - 1.6) * s,
                                       width: 3.2 * s, height: 3.2 * s))
        }
    }

    /// A scratch mark: three parallel claw streaks with a slight slant.
    private static func drawScratch(_ ctx: CGContext, at p: NSPoint, angle: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        ctx.setAlpha(alpha) // scales the cached color's alpha (0.45) → 0.45 * alpha
        ctx.setStrokeColor(scratchColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        let len: CGFloat = 16
        for i in 0 ..< 3 {
            let x = CGFloat(i - 1) * 4
            ctx.move(to: CGPoint(x: x, y: -len / 2))
            ctx.addLine(to: CGPoint(x: x + 1.5, y: len / 2))
        }
        ctx.strokePath()
    }
}
