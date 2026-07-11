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
        statusItem.button?.title = "🐱"
        let menu = NSMenu()
        menu.addItem(withTitle: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Neco", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func togglePause() { paused.toggle() }

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !paused else { return }
        neko.update(mouse: NSEvent.mouseLocation)
        reposition()
        view.needsDisplay = true
    }

    private func reposition() {
        panel.setFrameOrigin(NSPoint(x: neko.pos.x - side / 2, y: neko.pos.y - side / 2))
    }
}

@main
enum Neco {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory) // menu bar only; no dock icon
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
