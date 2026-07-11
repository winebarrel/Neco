import AppKit

// The cat's brain. Neco chases the mouse cursor and, when it catches up, runs the
// original oneko idle chain: sit -> (groom at a wall) -> paw -> scratch -> yawn ->
// sleep, waking with a startle the moment the cursor moves.

enum Tuning {
    static let scale: CGFloat = 2                 // sprite is 32x32; draw at 2x for chunky pixels
    static let speed: CGFloat = 6.0               // pixels per 60fps tick
    static let stopDistance: CGFloat = 24         // "caught the cursor" threshold
    static let wakeDistance: CGFloat = 40         // cursor must move this far to wake a sleeping cat
    static let edgeMargin: CGFloat = 24           // how close to a screen edge counts as "at the wall"

    // Idle-chain durations, in seconds. Mirror oneko.h (there 1 tick ~= 0.125s):
    // STOP 4, JARE 10, KAKI 4, AKUBI 6, AWAKE 3, TOGI 10.
    static let stopTime = 0.5
    static let jareTime = 1.25
    static let kakiTime = 0.5
    static let akubiTime = 0.75
    static let awakeTime = 0.375
    static let togiTime = 1.25

    static let animTicks = 7                       // run/idle frame swap cadence (~8fps, like the original)
    static let sleepAnimTicks = 30                 // slower sleeping breath
}

@MainActor
final class Neko {
    enum Motion { case running, awake, stop, jare, kaki, akubi, sleep, togi }

    private static let dirs = ["right", "upright", "up", "upleft", "left", "dwleft", "down", "dwright"]

    var pos: NSPoint
    private(set) var motion: Motion = .running
    private var dir = "down"          // 8-way facing while running
    private var togiDir = "d"         // u/d/l/r wall being groomed
    private var headingDx: CGFloat = 0
    private var headingDy: CGFloat = 0
    private var tick = 0
    private var stateStart = 0

    init(pos: NSPoint) { self.pos = pos }

    private var stateAge: Double { Double(tick - stateStart) / 60.0 }

    private func setState(_ m: Motion) {
        motion = m
        stateStart = tick
    }

    func update(mouse: NSPoint) {
        tick += 1
        let dx = mouse.x - pos.x
        let dy = mouse.y - pos.y
        let dist = hypot(dx, dy)

        switch motion {
        case .running:
            if dist <= Tuning.stopDistance {
                setState(.stop)
            } else {
                dir = Neko.direction(dx: dx, dy: dy)
                headingDx = dx; headingDy = dy
                let step = min(Tuning.speed, dist)
                pos.x += dx / dist * step
                pos.y += dy / dist * step
            }

        case .awake:
            if stateAge >= Tuning.awakeTime {
                dir = Neko.direction(dx: dx, dy: dy)
                setState(.running)
            }

        case .stop:
            if dist > Tuning.stopDistance { setState(.awake) }
            else if stateAge >= Tuning.stopTime { chooseAfterStop() }

        case .jare:
            if dist > Tuning.stopDistance { setState(.awake) }
            else if stateAge >= Tuning.jareTime { setState(.kaki) }

        case .togi:
            if dist > Tuning.stopDistance { setState(.awake) }
            else if stateAge >= Tuning.togiTime { setState(.kaki) }

        case .kaki:
            if dist > Tuning.stopDistance { setState(.awake) }
            else if stateAge >= Tuning.kakiTime { setState(.akubi) }

        case .akubi:
            if dist > Tuning.stopDistance { setState(.awake) }
            else if stateAge >= Tuning.akubiTime { setState(.sleep) }

        case .sleep:
            if dist > Tuning.wakeDistance { setState(.awake) }
        }
    }

    /// Leaving STOP: groom if the cat has run up against a screen edge, else paw.
    private func chooseAfterStop() {
        let screen = NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
        if let f = screen?.frame {
            let m = Tuning.edgeMargin
            if headingDx < 0, pos.x - f.minX <= m { togiDir = "l"; return setState(.togi) }
            if headingDx > 0, f.maxX - pos.x <= m { togiDir = "r"; return setState(.togi) }
            if headingDy > 0, f.maxY - pos.y <= m { togiDir = "u"; return setState(.togi) }
            if headingDy < 0, pos.y - f.minY <= m { togiDir = "d"; return setState(.togi) }
        }
        setState(.jare)
    }

    /// Which sprite to show right now.
    var frame: String {
        let phase = (tick / Tuning.animTicks) % 2
        switch motion {
        case .running: return dir + (phase == 0 ? "1" : "2")
        case .awake:   return "awake"
        case .stop:    return "mati2"
        case .jare:    return phase == 0 ? "jare2" : "mati2"   // paw out, then settle
        case .kaki:    return phase == 0 ? "kaki1" : "kaki2"   // scratch behind the ear
        case .akubi:   return "mati3"                          // yawn reuses mati3, as in oneko
        case .sleep:   return (tick / Tuning.sleepAnimTicks) % 2 == 0 ? "sleep1" : "sleep2"
        case .togi:
            let n = phase == 0 ? "1" : "2"
            switch togiDir {
            case "u": return "utogi" + n
            case "d": return "dtogi" + n
            case "l": return "ltogi" + n
            default:  return "rtogi" + n
            }
        }
    }

    private static func direction(dx: CGFloat, dy: CGFloat) -> String {
        let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        return dirs[((sector % 8) + 8) % 8]
    }
}
