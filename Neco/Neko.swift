import AppKit

// The cat's brain. Neco chases the mouse cursor and, when it catches up, runs the
// original oneko idle chain: sit -> (groom at a wall) -> paw -> scratch -> yawn ->
// sleep, waking with a startle the moment the cursor moves.

enum Tuning {
    static let scale: CGFloat = 2 // sprite is 32x32; draw at 2x for chunky pixels
    static let speed: CGFloat = 6.0 // pixels per 60fps tick
    static let stopDistance: CGFloat = 24 // "caught the cursor" threshold
    static let wakeDistance: CGFloat = 40 // cursor must move this far to wake a sleeping cat
    static let edgeMargin: CGFloat = 24 // how close to a screen edge counts as "at the wall"
    static let togiChance = 0.5 // when not at a wall, chance of scratching claws (togi) instead of pawing (jare) on stop

    // Idle-chain durations, in seconds. Mirror oneko.h (there 1 tick ~= 0.125s):
    // STOP 4, JARE 10, KAKI 4, AKUBI 6, AWAKE 3, TOGI 10.
    static let stopTime = 0.5
    static let jareTime = 1.25
    static let kakiTime = 0.5
    static let akubiTime = 0.75
    static let awakeTime = 0.375
    static let togiTime = 1.25

    static let animTicks = 7 // run/idle frame swap cadence (~8fps, like the original)
    static let sleepAnimTicks = 30 // slower sleeping breath

    /// Wander mode: instead of the cursor, chase a random on-screen point; once caught,
    /// linger this long (seconds) before picking a new one and running off again.
    static let wanderDwellRange = 0.4 ... 2.0
}

@MainActor
final class Neko {
    enum Motion { case running, awake, stop, jare, kaki, akubi, sleep, togi }

    private static let dirs = ["right", "upright", "up", "upleft", "left", "dwleft", "down", "dwright"]

    var pos: NSPoint
    private(set) var motion: Motion = .running
    private var dir = "down" // 8-way facing while running
    private var togiDir = "d" // u/d/l/r wall being groomed
    private var headingDx: CGFloat = 0
    private var headingDy: CGFloat = 0
    private var tick = 0
    private var stateStart = 0

    /// Wander mode: chase random on-screen points instead of the cursor. Turning it on
    /// immediately picks a first destination so the cat sets off right away.
    var wandering = false {
        didSet {
            guard wandering, wandering != oldValue else { return }
            pickWanderTarget()
        }
    }

    private var wanderTarget = NSPoint.zero
    private var wanderDwell = 0.0 // seconds to linger at the current target before moving on
    private var idleSince = 0 // tick the cat last stopped moving (for the dwell timer)

    init(pos: NSPoint) {
        self.pos = pos
    }

    private var stateAge: Double {
        Double(tick - stateStart) / 60.0
    }

    /// The cat is on the move; drops paw prints behind it (see LitterField).
    var isRunning: Bool {
        if case .running = motion {
            true
        } else {
            false
        }
    }

    /// The cat is sharpening its claws (togi): at a screen edge, or — per
    /// Tuning.togiChance — at a random stop anywhere. Scratch marks drop in this state.
    var isClawing: Bool {
        switch motion {
        case .togi: true
        default: false
        }
    }

    private func setState(_ m: Motion) {
        motion = m
        stateStart = tick
    }

    /// The cat is heading somewhere: running toward a target, or waking to do so.
    private var isMoving: Bool {
        switch motion {
        case .running, .awake: true
        default: false
        }
    }

    func update(mouse rawMouse: NSPoint) {
        tick += 1
        let mouse = wandering ? advanceWander() : rawMouse

        let dx = mouse.x - pos.x
        let dy = mouse.y - pos.y
        let dist = hypot(dx, dy)

        switch motion {
        case .running:
            chase(dx: dx, dy: dy, dist: dist)

        case .awake:
            if stateAge >= Tuning.awakeTime {
                dir = Neko.direction(dx: dx, dy: dy)
                setState(.running)
            }

        case .stop:
            if dist > Tuning.stopDistance {
                setState(.awake)
            } else if stateAge >= Tuning.stopTime {
                chooseAfterStop()
            }

        case .jare, .togi, .kaki, .akubi:
            advanceIdleChain(dist: dist)

        case .sleep:
            if dist > Tuning.wakeDistance {
                setState(.awake)
            }
        }
    }

    /// Move toward the cursor, or sit down once close enough.
    private func chase(dx: CGFloat, dy: CGFloat, dist: CGFloat) {
        guard dist > Tuning.stopDistance else {
            setState(.stop)
            return
        }
        dir = Neko.direction(dx: dx, dy: dy)
        headingDx = dx
        headingDy = dy
        let step = min(Tuning.speed, dist)
        pos.x += dx / dist * step
        pos.y += dy / dist * step
    }

    /// One idle-chain step: wake if the cursor moved away, else advance the chain
    /// (jare -> kaki -> akubi -> sleep; togi rejoins at kaki) after its time.
    private func advanceIdleChain(dist: CGFloat) {
        if dist > Tuning.stopDistance {
            setState(.awake)
            return
        }
        let until: Double
        let next: Motion
        switch motion {
        case .jare: (until, next) = (Tuning.jareTime, .kaki)
        case .togi: (until, next) = (Tuning.togiTime, .kaki)
        case .kaki: (until, next) = (Tuning.kakiTime, .akubi)
        default: (until, next) = (Tuning.akubiTime, .sleep) // .akubi
        }
        if stateAge >= until {
            setState(next)
        }
    }

    /// Leaving STOP: groom if the cat has run up against a screen edge. Otherwise, at
    /// random, sharpen claws (togi) facing a random way, else paw (jare).
    private func chooseAfterStop() {
        let screen = NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
        if let f = screen?.frame {
            let m = Tuning.edgeMargin
            if headingDx < 0, pos.x - f.minX <= m {
                togiDir = "l"; return setState(.togi)
            }
            if headingDx > 0, f.maxX - pos.x <= m {
                togiDir = "r"; return setState(.togi)
            }
            if headingDy > 0, f.maxY - pos.y <= m {
                togiDir = "u"; return setState(.togi)
            }
            if headingDy < 0, pos.y - f.minY <= m {
                togiDir = "d"; return setState(.togi)
            }
        }
        if Double.random(in: 0 ..< 1) < Tuning.togiChance {
            togiDir = ["u", "d", "l", "r"].randomElement() ?? "d"
            setState(.togi)
        } else {
            setState(.jare)
        }
    }

    /// Wander mode's stand-in for the cursor. The cat keeps moving until it settles,
    /// lingers for wanderDwell, then a fresh destination pulls the target away and wakes
    /// it — the same way real cursor movement does. Returns the current target point.
    private func advanceWander() -> NSPoint {
        if isMoving {
            idleSince = tick
        } else if Double(tick - idleSince) / 60.0 >= wanderDwell {
            pickWanderTarget()
        }
        return wanderTarget
    }

    /// Pick a fresh random destination for wander mode: a random point (kept off the
    /// very edges) on a randomly chosen screen. Reset the dwell clock so the cat runs
    /// off before it is eligible to settle again.
    private func pickWanderTarget() {
        let frame = (NSScreen.screens.randomElement() ?? NSScreen.main)?.frame ?? .zero
        let m = Tuning.edgeMargin
        wanderTarget = NSPoint(
            x: .random(in: (frame.minX + m) ... max(frame.minX + m, frame.maxX - m)),
            y: .random(in: (frame.minY + m) ... max(frame.minY + m, frame.maxY - m))
        )
        wanderDwell = .random(in: Tuning.wanderDwellRange)
        idleSince = tick
    }

    /// Which sprite to show right now.
    var frame: String {
        let phase = (tick / Tuning.animTicks) % 2
        switch motion {
        case .running: return dir + (phase == 0 ? "1" : "2")
        case .awake: return "awake"
        case .stop: return "mati2"
        case .jare: return phase == 0 ? "jare2" : "mati2" // paw out, then settle
        case .kaki: return phase == 0 ? "kaki1" : "kaki2" // scratch behind the ear
        case .akubi: return "mati3" // yawn reuses mati3, as in oneko
        case .sleep: return (tick / Tuning.sleepAnimTicks) % 2 == 0 ? "sleep1" : "sleep2"
        case .togi:
            let n = phase == 0 ? "1" : "2"
            switch togiDir {
            case "u": return "utogi" + n
            case "d": return "dtogi" + n
            case "l": return "ltogi" + n
            default: return "rtogi" + n
            }
        }
    }

    private static func direction(dx: CGFloat, dy: CGFloat) -> String {
        let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        return dirs[((sector % 8) + 8) % 8]
    }
}
