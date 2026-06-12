import AppKit
import QuartzCore   // CACurrentMediaTime — line-pet animation clock
import Effects      // sill: drawLinePets / LinePet

// The ring overlay + its driver.
//
// BorderController resolves the frontmost third-party window (front-to-back
// z-order from CGWindowList, skipping halo's own + excluded apps + tiny
// popups), hugs it with a transparent click-through overlay, and flashes
// on focus change. Driven by WindowServerEvents: each MOVE/RESIZE re-hugs
// (smooth follow during a drag), each FRONT/REORDER re-resolves the focused
// window. The ring's look (color / width / glow / cycle / flash) is owned
// by BorderFX — halo's local animator over sill's shared effect catalog
// (`Effects.EffectSpec`).
//
// Margin: the overlay frame is the window rect expanded by `glowPad` so the
// glow can bloom OUTWARD past the window edge (the ring itself sits `pad`
// outside the window edge).
private let glowPad: CGFloat = 24

final class BorderController {
    private var cfg: HaloConfig
    private let events: WindowServerEvents
    private let overlay = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                   backing: .buffered, defer: true)
    private let fx = BorderFX()
    private let shake = WindowShake()
    private let focusSound = FocusSound()
    private let ring: RingView
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private var lastWID: UInt32 = 0
    private var didFirstResolve = false
    private var lastConfigMtime: Date?

    init(config: HaloConfig, events: WindowServerEvents) {
        self.cfg = config
        self.events = events
        self.ring = RingView(config: config, fx: fx)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true               // click-through
        overlay.level = .floating
        overlay.hasShadow = false
        overlay.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]  // desktop-local (rides the Space slide)
        overlay.contentView = ring

        fx.onRepaint = { [weak ring] in ring?.needsDisplay = true }
        applyConfig(config)
        lastConfigMtime = Self.configMtime()
    }

    /// (Re)apply a config to fx / shake / ring. One path for both launch
    /// and hot-reload, so every tunable lands the same way.
    private func applyConfig(_ c: HaloConfig) {
        cfg = c
        ring.cfg = c
        shake.amplitude = c.shakeAmplitude
        shake.durationMs = c.shakeDurationMs
        fx.configure(effectName: c.effect, glow: c.glow, width: c.width,
                     cycleSeconds: c.cycleSeconds, cycleColors: c.cycleColors,
                     minWidth: c.minWidth, maxWidth: c.maxWidth, baseColor: c.color,
                     hasPets: !c.linePets.isEmpty)
        focusSound.configure(path: c.sound, volume: c.soundVolume)
        ring.needsDisplay = true
    }

    private static let configPath =
        ("~/.config/halo/config.toml" as NSString).expandingTildeInPath
    private static func configMtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: configPath))?[.modificationDate] as? Date
    }

    /// Hot-reload: re-read + re-apply config when its mtime changes.
    /// Driven off the existing 0.4s safety-net poll (≤0.4s latency), which
    /// also covers editors that atomically replace the file (mtime/inode
    /// changes regardless). halo has no CLI/DNC client like facet, so
    /// polling the file's mtime is the natural trigger.
    private func reloadIfConfigChanged() {
        let m = Self.configMtime()
        guard m != lastConfigMtime else { return }
        lastConfigMtime = m
        Log.line("config changed → hot-reload")
        applyConfig(HaloConfig.load())
        // If shake was just turned on but Accessibility isn't granted,
        // fire() would silently no-op — say so (grant takes effect live,
        // no restart, since fire() re-checks trust each time).
        if cfg.shake && !WindowShake.trusted {
            Log.line("shake is on but Accessibility isn't granted — enable halo in "
                + "System Settings → Privacy & Security → Accessibility (no restart needed)")
        }
    }

    /// A window-server event arrived (fired on the main thread).
    func onEvent(_ event: UInt32) {
        if event != WindowServerEvents.MOVE { Log.debug("evt-\(event)") }
        update(trigger: "event-\(event)", resubscribe: event == WindowServerEvents.FRONT)
        // 1508 (app-switch) / 808 (same-app window-switch) fire BEFORE the
        // window server's z-order settles, so the immediate re-resolve reads
        // the OLD front and misses (then the 0.4s poll catches it — late).
        // Re-resolve a few times as it commits; the first that sees the new
        // front logs + flashes. (JankyBorders defers ~50ms for this.)
        if event == WindowServerEvents.FRONT || event == WindowServerEvents.REORDER {
            for ms in [16, 40, 80] {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) { [weak self] in
                    self?.update(trigger: "event-\(event)+\(ms)ms", resubscribe: false)
                }
            }
        }
    }

    /// Periodic safety-net pass (re-subscribe the on-screen set + re-hug),
    /// plus the hot-reload mtime check.
    func poll() { reloadIfConfigChanged(); update(trigger: "poll", resubscribe: true) }

    /// One pass over a SINGLE window-server snapshot — drives both the
    /// per-window (re)subscription AND the focused-window resolve.
    private func update(trigger: String, resubscribe: Bool) {
        let t0 = ProcessInfo.processInfo.systemUptime
        let info = windowInfo()
        let resolveMs = (ProcessInfo.processInfo.systemUptime - t0) * 1000
        if trigger == "poll" { Log.debug(String(format: "resolve %.2fms (%d windows)", resolveMs, info.count)) }

        if resubscribe {
            events.requestWindows(info.compactMap { $0[kCGWindowNumber as String] as? UInt32 })
        }
        guard let (wid, pid, cg) = focused(in: info) else { overlay.orderOut(nil); lastWID = 0; return }
        let screenH = NSScreen.screens.first?.frame.height ?? 0      // CG (y-down) → Cocoa (y-up)
        let cocoa = CGRect(x: cg.origin.x, y: screenH - cg.origin.y - cg.height,
                           width: cg.width, height: cg.height)
        overlay.setFrame(cocoa.insetBy(dx: -glowPad, dy: -glowPad), display: true)
        if !overlay.isVisible { overlay.orderFrontRegardless() }
        ring.needsDisplay = true
        if wid != lastWID {
            lastWID = wid
            Log.debug(String(format: "focus → wid=%u via %@ (resolve %.2fms)", wid, trigger, resolveMs))
            fx.flash()
            // Gate the shake + sound on didFirstResolve (set once, never
            // reset) — NOT on lastWID, which the no-focus branch above resets
            // to 0; that would suppress them after any transient defocus.
            // didFirstResolve also keeps both off the launch resolve (halo
            // just started — you didn't change focus).
            if didFirstResolve { focusSound.play() }
            if cfg.shake && didFirstResolve { shake.fire(pid: pid_t(pid), wid: wid) }
        }
        didFirstResolve = true
    }

    /// Frontmost layer-0 window not owned by us / not excluded, from a snapshot.
    /// Returns its CGWindowID, owning pid, and CG bounds.
    private func focused(in info: [[String: Any]]) -> (UInt32, Int32, CGRect)? {
        for d in info {
            guard let pid = d[kCGWindowOwnerPID as String] as? Int32, pid != selfPID,
                  let wid = d[kCGWindowNumber as String] as? UInt32,
                  !cfg.isExcluded(pid: pid),
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  w >= cfg.minSize, h >= cfg.minSize
            else { continue }
            return (wid, pid, CGRect(x: x, y: y, width: w, height: h))
        }
        return nil
    }

    /// On-screen, layer-0 (normal) windows, front-to-back.
    private func windowInfo() -> [[String: Any]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.filter { ($0[kCGWindowLayer as String] as? Int ?? 0) == 0 }
    }
}

/// The rounded stroke. Reads its style live from BorderFX (color / width /
/// glow / cycle / flash), so all of facet's border effects apply.
final class RingView: NSView {
    var cfg: HaloConfig                 // var: swapped on hot-reload
    private let fx: BorderFX

    init(config: HaloConfig, fx: BorderFX) { self.cfg = config; self.fx = fx; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Ring sits `pad` outside the window edge; the window edge is
        // `glowPad` inside the overlay bounds.
        let rect = bounds.insetBy(dx: glowPad - cfg.pad, dy: glowPad - cfg.pad)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cfg.cornerRadius, yRadius: cfg.cornerRadius)
        path.lineWidth = fx.width
        let stroke = fx.color
        stroke.setStroke()
        // Isolate the glow shadow to the ring stroke so it doesn't bloom
        // under the pets drawn next.
        NSGraphicsContext.saveGraphicsState()
        if fx.glowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = stroke
            shadow.shadowBlurRadius = max(6, fx.width * 4)
            shadow.set()
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Arcade pets orbiting the ring (opt-in via `line-pets`). They ride
        // the same `rect` the ring strokes, so they walk ON the border. The
        // shared sill drawing; halo owns only the rect + the redraw cadence
        // (BorderFX keeps its timer alive while pets are configured).
        if !cfg.linePets.isEmpty {
            // Derive pt/s from a desired lap time so the orbit feels equally
            // lively at any window size — a constant pt/s would crawl on a big
            // window and sprint on a small one.
            let perim = 2 * (rect.width + rect.height)
            let speed = perim / max(0.5, cfg.petLapSeconds)
            drawLinePets(cfg.linePets, on: rect, now: CACurrentMediaTime(),
                         scale: cfg.petScale, speed: speed)
        }
    }
}
