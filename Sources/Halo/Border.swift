import AppKit

// The ring overlay + its driver.
//
// BorderController resolves the frontmost third-party window (front-to-back
// z-order from CGWindowList, skipping halo's own + excluded apps + tiny
// popups), hugs it with a transparent click-through overlay, and pulses
// the ring on focus change. It is driven by WindowServerEvents: each
// MOVE/RESIZE re-hugs (smooth follow during a drag), each FRONT-change
// re-resolves the focused window and flashes.
final class BorderController {
    private let cfg: HaloConfig
    private let events: WindowServerEvents
    private let overlay = NSWindow(contentRect: .zero, styleMask: [.borderless],
                                   backing: .buffered, defer: true)
    private let ring: RingView
    private let selfPID = ProcessInfo.processInfo.processIdentifier
    private var lastWID: UInt32 = 0
    private var flashTimer: Timer?

    init(config: HaloConfig, events: WindowServerEvents) {
        self.cfg = config
        self.events = events
        self.ring = RingView(config: config)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true               // click-through
        overlay.level = .floating
        overlay.hasShadow = false
        // Desktop-local on purpose (NOT .canJoinAllSpaces): the ring rides
        // its own Space's switch animation instead of being composited
        // across, which avoids the worst of the Space-switch flicker.
        overlay.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
        overlay.contentView = ring
    }

    /// A window-server event arrived (fired on the main thread). A
    /// front-change also refreshes the per-window subscription so the new
    /// focused window starts emitting MOVE/RESIZE.
    func onEvent(_ event: UInt32) {
        if event != WindowServerEvents.MOVE { Log.debug("evt-\(event)") }   // diagnostic (MOVE floods during a drag → skip)
        // trigger label carries the exact event code so the log shows
        // which signal caught each focus change (event-1508 app-switch /
        // event-808 same-app reorder / event-806 move / poll = safety net).
        update(trigger: "event-\(event)", resubscribe: event == WindowServerEvents.FRONT)

        // A front-process change (1508, app-switch) AND a same-app z-order
        // change (808, window-switch) both fire BEFORE the window server's
        // z-order settles, so the immediate re-resolve above still reads the
        // OLD front and misses (then the 0.4s poll catches it — visibly late).
        // Re-resolve a few times as it commits; the first pass that sees the
        // new front logs + flashes. JankyBorders defers ~50ms for this.
        if event == WindowServerEvents.FRONT || event == WindowServerEvents.REORDER {
            for ms in [16, 40, 80] {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) { [weak self] in
                    self?.update(trigger: "event-\(event)+\(ms)ms", resubscribe: false)
                }
            }
        }
    }

    /// Periodic safety-net pass (re-subscribe the on-screen set + re-hug),
    /// so windows opened after launch start emitting and a missed event
    /// can't leave the ring stale.
    func poll() { update(trigger: "poll", resubscribe: true) }

    /// One pass over a SINGLE window-server snapshot — it drives both the
    /// per-window (re)subscription AND the focused-window resolve, so a
    /// front-change costs ONE CGWindowList query, not two.
    private func update(trigger: String, resubscribe: Bool) {
        let t0 = ProcessInfo.processInfo.systemUptime
        let info = windowInfo()
        let resolveMs = (ProcessInfo.processInfo.systemUptime - t0) * 1000
        if trigger == "poll" {        // sampled cost readout (every ~0.4s, not per drag frame)
            Log.debug(String(format: "resolve %.2fms (%d windows)", resolveMs, info.count))
        }

        if resubscribe {
            events.requestWindows(info.compactMap { $0[kCGWindowNumber as String] as? UInt32 })
        }
        guard let (wid, cg) = focused(in: info) else { overlay.orderOut(nil); lastWID = 0; return }
        let screenH = NSScreen.screens.first?.frame.height ?? 0      // CG (y-down) → Cocoa (y-up)
        let cocoa = CGRect(x: cg.origin.x, y: screenH - cg.origin.y - cg.height,
                           width: cg.width, height: cg.height)
        overlay.setFrame(cocoa.insetBy(dx: -cfg.pad, dy: -cfg.pad), display: true)
        if !overlay.isVisible { overlay.orderFrontRegardless() }
        ring.needsDisplay = true
        if wid != lastWID {
            lastWID = wid
            Log.debug(String(format: "focus → wid=%u via %@ (resolve %.2fms)", wid, trigger, resolveMs))
            flash()
        }
    }

    /// Frontmost layer-0 window not owned by us / not excluded, from a snapshot.
    private func focused(in info: [[String: Any]]) -> (UInt32, CGRect)? {
        for d in info {
            guard let pid = d[kCGWindowOwnerPID as String] as? Int32, pid != selfPID,
                  let wid = d[kCGWindowNumber as String] as? UInt32,
                  let owner = d[kCGWindowOwnerName as String] as? String,
                  !cfg.excludedApps.contains(owner),
                  let b = d[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  w >= cfg.minSize, h >= cfg.minSize
            else { continue }
            return (wid, CGRect(x: x, y: y, width: w, height: h))
        }
        return nil
    }

    /// On-screen, layer-0 (normal) windows, front-to-back.
    private func windowInfo() -> [[String: Any]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return raw.filter { ($0[kCGWindowLayer as String] as? Int ?? 0) == 0 }
    }

    private func flash() {
        guard cfg.flashMs > 0 else { return }
        flashTimer?.invalidate()
        ring.flash = 1
        let start = ProcessInfo.processInfo.systemUptime
        let duration = Double(cfg.flashMs) / 1000.0
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            self.ring.flash = max(0, 1 - CGFloat(elapsed / duration))
            self.ring.needsDisplay = true
            if elapsed >= duration { t.invalidate() }
        }
    }
}

/// The rounded stroke. `flash` (1→0) brightens toward the flash colour,
/// thickens the line, and (if enabled) blooms a short glow.
final class RingView: NSView {
    var flash: CGFloat = 0
    private let cfg: HaloConfig

    init(config: HaloConfig) { self.cfg = config; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: cfg.pad, dy: cfg.pad)
        let path = NSBezierPath(roundedRect: rect, xRadius: cfg.cornerRadius, yRadius: cfg.cornerRadius)
        path.lineWidth = cfg.width + flash * cfg.flashWidth
        let stroke = cfg.color.blended(withFraction: flash, of: cfg.flashColor) ?? cfg.color
        stroke.setStroke()
        if cfg.glow, flash > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = stroke.withAlphaComponent(flash)
            shadow.shadowBlurRadius = 12
            shadow.set()
        }
        path.stroke()
    }
}
