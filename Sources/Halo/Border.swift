import AppKit
import QuartzCore   // CACurrentMediaTime — line-pet animation clock
import Effects      // sill: drawLinePets / LinePet / NSColor(HexColor)
import HaloCore

// The ring overlay + its driver.
//
// BorderController resolves the frontmost third-party window (front-to-back
// z-order from CGWindowList, skipping halo's own + excluded apps + tiny
// popups), hugs it with a transparent click-through overlay, and flashes
// on focus change. Driven by WindowServerEvents: each MOVE/RESIZE re-hugs
// (smooth follow during a drag), each FRONT/REORDER re-resolves the focused
// window. The ring's look (color / width / glow / cycle / flash) is owned
// by BorderFX — halo's local animator over sill's shared effect catalog
// (`Effects.EffectSpec`). The overlay ↔ ring arithmetic is
// `HaloCore.RingGeometry`; the pick itself is `HaloCore.FocusResolver`.
//
// BorderController is the ONE owner of the config: it loads it, hot-reloads
// it off its own 0.4s safety-net poll, and hands every tunable to fx /
// shake / ring / sound through `applyConfig`.
//
// @MainActor: every entry point (events, timers, the settle re-resolves)
// arrives on the main run loop; the timer / dispatch closures re-enter via
// `MainActor.assumeIsolated`, the family's pattern (facet's BorderFX).

@MainActor
final class BorderController {
    private var cfg: HaloConfig
    private let events: WindowServerEvents
    private var safetyNet: Timer?
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
    /// The ONE 30 Hz redraw heartbeat — pumps `ring.needsDisplay` while the
    /// border animates (rainbow / breathing / flash) OR line-pets orbit. Both
    /// ride a single wall clock in `RingView.draw`; this is just the cadence,
    /// not an animator (the math is sill's clockless `resolveBorder`).
    private var redrawTimer: Timer?

    /// The config as last applied (launch or hot-reload).
    var config: HaloConfig { cfg }

    init(events: WindowServerEvents) {
        let config = HaloConfig.load()
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

        applyConfig(config)
        lastConfigMtime = Self.configMtime()
    }

    /// First resolve + the safety net (yabai-style): periodically
    /// re-subscribe the on-screen set + re-hug, so windows opened after
    /// launch start emitting MOVE/RESIZE and a missed event can't leave the
    /// ring stale. The live, smooth tracking still comes from the ~5ms
    /// events. The same tick carries the config mtime check (hot-reload).
    func start() {
        poll()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyNet = timer
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
                     minWidth: c.minWidth, maxWidth: c.maxWidth, baseColor: NSColor(c.color))
        focusSound.configure(path: c.sound, volume: c.soundVolume)
        ring.needsDisplay = true
        syncRedraw()
    }

    /// Start / stop the 30 Hz redraw heartbeat to match what's animating now
    /// (border cycle / breath / flash, or line-pets orbiting forever while
    /// configured). Called whenever the animated state can change: configure,
    /// focus flash. A static border with no pets parks the timer entirely.
    private func syncRedraw() {
        if fx.animating(at: CACurrentMediaTime()) || !cfg.linePets.isEmpty {
            startRedraw()
        } else {
            stopRedraw()
        }
    }

    private func startRedraw() {
        guard redrawTimer == nil else { return }
        // 30 Hz, .common so it keeps ticking during interaction. Self-stops in
        // the tick once nothing animates (the flash burst settles by wall-clock).
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ring.needsDisplay = true
                if !(self.fx.animating(at: CACurrentMediaTime()) || !self.cfg.linePets.isEmpty) {
                    self.stopRedraw()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        redrawTimer = t
    }

    private func stopRedraw() { redrawTimer?.invalidate(); redrawTimer = nil }

    private static func configMtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: HaloConfig.configFilePath))?[.modificationDate] as? Date
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
                    MainActor.assumeIsolated {
                        self?.update(trigger: "event-\(event)+\(ms)ms", resubscribe: false)
                    }
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
            events.requestWindows(info.map(\.id))
        }
        guard let front = FocusResolver.focused(in: info, selfPID: selfPID, minSize: cfg.minSize,
                                                isExcluded: isExcluded)
        else { overlay.orderOut(nil); lastWID = 0; return }
        let (wid, pid) = (front.id, front.ownerPID)
        let screenH = NSScreen.screens.first?.frame.height ?? 0      // CG (y-down) → Cocoa (y-up)
        overlay.setFrame(RingGeometry.overlayFrame(hugging: front.bounds, screenHeight: screenH),
                         display: true)
        if !overlay.isVisible { overlay.orderFrontRegardless() }
        ring.needsDisplay = true
        if wid != lastWID {
            lastWID = wid
            Log.debug(String(format: "focus → wid=%u via %@ (resolve %.2fms)", wid, trigger, resolveMs))
            fx.flash()
            syncRedraw()
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

    /// `[exclude].apps` check for a candidate's pid. Resolves the bundle
    /// id lazily — only when an exclusion is configured — so the common
    /// empty case never touches NSRunningApplication.
    private func isExcluded(pid: Int32) -> Bool {
        guard !cfg.excludedApps.isEmpty else { return false }
        let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        return cfg.isExcluded(bundleID: bid)
    }

    /// On-screen, layer-0 (normal) windows, front-to-back, as the pure
    /// snapshot `FocusResolver` reads. Rows missing an id / pid / bounds
    /// are dropped here (they can't be hugged anyway).
    private func windowInfo() -> [WindowSnapshot] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? Int32,
                  let wid = d[kCGWindowNumber as String] as? UInt32,
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { return nil }
            return WindowSnapshot(id: wid, ownerPID: pid, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
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
        let rect = RingGeometry.ringRect(in: bounds, pad: cfg.pad)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: cfg.cornerRadius, yRadius: cfg.cornerRadius)
        // ONE wall-clock sample for the whole frame: the border color/width and
        // the pets below walk on the exact same `now` (the "one clock").
        let now = CACurrentMediaTime()
        let style = fx.sample(at: now)
        path.lineWidth = style.width
        let stroke = style.color
        stroke.setStroke()
        // Isolate the glow shadow to the ring stroke so it doesn't bloom
        // under the pets drawn next.
        NSGraphicsContext.saveGraphicsState()
        if fx.glowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = stroke
            shadow.shadowBlurRadius = max(6, style.width * 4)
            shadow.set()
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Arcade pets orbiting the ring (opt-in via `line-pets`). They ride
        // the same `rect` the ring strokes, so they walk ON the border. The
        // shared sill drawing; halo owns only the rect + the redraw cadence
        // (BorderFX keeps its timer alive while pets are configured).
        if !cfg.linePets.isEmpty {
            drawLinePets(cfg.linePets, on: rect, now: now, scale: cfg.petScale,
                         speed: PetOrbit.speed(around: rect, lapSeconds: cfg.petLapSeconds))
        }
    }
}
