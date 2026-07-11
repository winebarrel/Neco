import AppKit

// Neco: an xneko / oneko-style desktop pet for macOS. A cat lives in a small
// transparent, click-through panel and chases the mouse cursor. Sprites are the
// public-domain oneko "neko" bitmaps.
//
// The window setup (borderless non-activating panel, clear background, click
// through, all spaces, 60fps timer) follows ~/com/winebarrel/CursorIME.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var view: NekoView!
    private var neko: Neko!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var paused = false
    private var lastStatusFrame = ""

    private var side: CGFloat { CGFloat(Sprites.width) * Tuning.scale }

    func applicationDidFinishLaunching(_: Notification) {
        let m = NSEvent.mouseLocation
        neko = Neko(pos: NSPoint(x: m.x - 120, y: m.y - 120))

        view = NekoView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.neko = neko

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        reposition()
        panel.orderFrontRegardless()

        setupStatusItem()
        startTimer()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusImage()

        let menu = NSMenu()
        let pause = NSMenuItem(title: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        // Target NSApp, not self: AppDelegate does not implement terminate:, so a
        // self target would leave the item auto-disabled (greyed out).
        let quit = NSMenuItem(title: "Quit Neco", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    /// Mirror the desktop cat's current pose in the menu bar.
    private func updateStatusImage() {
        guard neko.frame != lastStatusFrame else { return }
        lastStatusFrame = neko.frame
        statusItem.button?.image = SpriteCache.menuBarImage(neko.frame)
    }

    @objc private func togglePause() { paused.toggle() }

    private func startTimer() {
        // Target/selector Timer: it fires on the run loop it is scheduled on (main),
        // so tick stays on the MainActor without an unchecked assumeIsolated.
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self,
                          selector: #selector(onTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func onTick() {
        guard !paused else { return }
        neko.update(mouse: NSEvent.mouseLocation)
        reposition()
        view.needsDisplay = true
        updateStatusImage()
    }

    private func reposition() {
        panel.setFrameOrigin(NSPoint(x: neko.pos.x - side / 2, y: neko.pos.y - side / 2))
    }
}

@main
enum Neco {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only; no dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
