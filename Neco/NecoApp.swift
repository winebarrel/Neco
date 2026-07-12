import AppKit
import SwiftUI

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

    // The mess overlay: a full-screen click-through panel below the cat that draws
    // the paw prints and scratch marks the cat leaves behind.
    private var litterPanel: NSPanel!
    private var litterView: LitterView!
    private let litter = LitterField()
    private var pawsItem: NSMenuItem!
    private var scratchItem: NSMenuItem!
    private var tick = 0

    private var side: CGFloat {
        CGFloat(Sprites.width) * Tuning.scale
    }

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

        setupLitterPanel()
        setupStatusItem()
        startTimer()
    }

    /// A full-screen, click-through overlay just below the cat, for its paw prints
    /// and scratch marks. It spans every screen so the mess follows the cat around.
    private func setupLitterPanel() {
        let d = UserDefaults.standard
        litter.pawsEnabled = d.object(forKey: "pawsEnabled") as? Bool ?? false
        litter.scratchEnabled = d.object(forKey: "scratchEnabled") as? Bool ?? false

        litterView = LitterView()
        litterView.field = litter

        litterPanel = NSPanel(
            contentRect: screensFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        litterPanel.isOpaque = false
        litterPanel.backgroundColor = .clear
        litterPanel.hasShadow = false
        // One level below the cat so the cat always walks on top of its own mess.
        litterPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        litterPanel.ignoresMouseEvents = true
        litterPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        litterPanel.contentView = litterView
        layoutLitterPanel()
        litterPanel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    private func screensFrame() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
    }

    private func layoutLitterPanel() {
        let frame = screensFrame()
        litterPanel.setFrame(frame, display: false)
        litterView.frame = NSRect(origin: .zero, size: frame.size)
        litterView.originOffset = frame.origin
    }

    @objc private func screensChanged() {
        layoutLitterPanel()
        litterView.needsDisplay = true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusImage()

        let menu = NSMenu()

        pawsItem = NSMenuItem(title: "Paw Prints", action: #selector(togglePaws), keyEquivalent: "")
        pawsItem.target = self
        pawsItem.state = litter.pawsEnabled ? .on : .off
        menu.addItem(pawsItem)

        scratchItem = NSMenuItem(title: "Scratch Marks", action: #selector(toggleScratch), keyEquivalent: "")
        scratchItem.target = self
        scratchItem.state = litter.scratchEnabled ? .on : .off
        menu.addItem(scratchItem)

        let clear = NSMenuItem(title: "Clear Mess", action: #selector(clearMess), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

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

    @objc private func togglePause() {
        paused.toggle()
    }

    @objc private func togglePaws() {
        litter.pawsEnabled.toggle()
        pawsItem.state = litter.pawsEnabled ? .on : .off
        UserDefaults.standard.set(litter.pawsEnabled, forKey: "pawsEnabled")
    }

    @objc private func toggleScratch() {
        litter.scratchEnabled.toggle()
        scratchItem.state = litter.scratchEnabled ? .on : .off
        UserDefaults.standard.set(litter.scratchEnabled, forKey: "scratchEnabled")
    }

    @objc private func clearMess() {
        litter.clear()
        litterView.needsDisplay = true
    }

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
        tick += 1
        neko.update(mouse: NSEvent.mouseLocation)
        reposition()
        view.needsDisplay = true
        updateStatusImage()

        // Invalidate only the patches around marks that appeared or vanished; refresh
        // fading marks at ~10fps. Cost scales with changed pixels, not screen area.
        for rect in litter.update(neko: neko) {
            litterView.invalidateGlobal(rect)
        }
        if tick % 6 == 0 {
            for rect in litter.fadingRects() {
                litterView.invalidateGlobal(rect)
            }
        }
    }

    private func reposition() {
        panel.setFrameOrigin(NSPoint(x: neko.pos.x - side / 2, y: neko.pos.y - side / 2))
    }
}

@main
struct NecoApp: App {
    // The overlay panel and status item are driven from AppDelegate; the adaptor
    // keeps it alive. Menu-bar only via LSUIElement, so no window is needed.
    // swiftlint:disable:next unused_declaration
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
