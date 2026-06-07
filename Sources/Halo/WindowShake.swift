import AppKit
import ApplicationServices
import Darwin

// `_AXUIElementGetWindow` (private ApplicationServices symbol, dlsym-bound)
// maps an AX window element to its CGWindowID — the same reconciliation
// facet uses (AXFocus/AXGeom) to line AX elements up with CGWindowList ids.
private typealias AXGetWindowFn =
    @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axGetWindow: AXGetWindowFn? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                          "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(sym, to: AXGetWindowFn.self)
}()

// Focus-shake — a quick horizontal jiggle of the FOCUSED WINDOW on
// focus change. A sibling-repo "satellite" of facet's reverted ④
// focus-shake (the satellite-features-live-in-sibling-repos decision):
// the border / flash effects live in halo, and so does this.
//
// Unlike halo's ring (a read-only click-through overlay), this MOVES
// the real window via AX `kAXPositionAttribute`, so it needs the
// Accessibility grant (`shake = false` in config keeps halo
// permission-free). It nudges POSITION ONLY — never size — and the
// decaying-sine taper lands the final write on the EXACT origin, so
// neighbours are never affected: halo has no tiling / reconcile to
// fight the move, and a co-running facet just sees the window return
// to its base frame.
//
//   x(p) = origin.x + amplitude · sin(2π·cycles·p) · (1 − p),  p ∈ [0,1]
//
// `p` is wall-clock progress over `durationMs`; the `(1 − p)` envelope
// decays the swing to zero and guarantees x(1) == origin.x. `y` is
// never touched (pure left-right shake). Chrome / Calendar and other
// lazy-AX apps won't surface a movable focused window → fire() no-ops
// on them (a known, accepted limitation).
//
// Not @MainActor: halo is single-threaded on the main run loop. fire()
// is called from BorderController on the main thread, and the timer
// runs on the main run loop, so every AX call stays on main.
final class WindowShake {
    /// Peak horizontal swing in points (config `shake-amplitude`).
    var amplitude: CGFloat = 10
    /// Total shake duration in ms (config `shake-duration-ms`).
    var durationMs: Double = 250

    private let cycles: CGFloat = 3.5      // oscillations across the duration
    private let hz: Double = 90            // AX-write frame rate

    private var timer: Timer?
    private var win: AXUIElement?
    private var origin: CGPoint = .zero
    private var startUptime: TimeInterval = 0

    // Deferred mouse-driven shake: a focus change while a button is held
    // could be a click (shake on release) or a drag (no shake). We hold
    // the decision here until the gesture ends.
    private var pending: (pid: pid_t, wid: CGWindowID)?
    private var armPoint: CGPoint = .zero
    private var gestureMonitor: Any?
    private let dragThreshold: CGFloat = 6   // pt of pointer travel ⇒ drag, not click

    /// Accessibility granted? (Required to move another app's window.)
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shake the window `wid` (the one the ring/flash resolved) owned by
    /// app `pid`. No-op without AX trust, or when the app won't surface a
    /// movable matching window.
    func fire(pid: pid_t, wid: CGWindowID) {
        guard AXIsProcessTrusted() else { return }

        // A focus change while a mouse button is held is mouse-driven:
        // either a plain click-to-focus (which SHOULD still shake) or the
        // start of a window drag (which must NOT — our kAXPosition sine
        // would land ON TOP of the OS's cursor-track and yank the window
        // off the cursor: the "DnD drift" against facet's observe-only
        // real-window drag). We can't tell click from drag until the
        // gesture ends, so defer the decision (no shake starts now, so a
        // drag never jerks). Keyboard / programmatic focus changes (no
        // button held) shake immediately, as before.
        if NSEvent.pressedMouseButtons != 0 {
            armDeferred(pid: pid, wid: wid)
            return
        }
        start(pid: pid, wid: wid)
    }

    /// Hold a mouse-driven focus shake until the gesture resolves: fire on
    /// mouse-up if the pointer stayed within `dragThreshold` (a click),
    /// drop it if it travelled past (a drag). One lazily-installed global
    /// monitor drives the decision and no-ops whenever nothing is pending.
    private func armDeferred(pid: pid_t, wid: CGWindowID) {
        pending = (pid, wid)
        armPoint = NSEvent.mouseLocation
        if gestureMonitor == nil {
            gestureMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] e in
                self?.onGesture(e)
            }
        }
    }

    private func onGesture(_ e: NSEvent) {
        guard pending != nil else { return }
        switch e.type {
        case .leftMouseDragged:
            let p = NSEvent.mouseLocation
            if hypot(p.x - armPoint.x, p.y - armPoint.y) > dragThreshold {
                pending = nil                      // became a drag → no shake
            }
        case .leftMouseUp:
            if let pend = pending {
                pending = nil
                start(pid: pend.pid, wid: pend.wid)  // was a click → shake now
            }
        default:
            break
        }
    }

    /// Begin the shake animation on the resolved window.
    private func start(pid: pid_t, wid: CGWindowID) {
        // Re-entrancy: snap any in-flight shake back to its origin
        // before starting the next, so a fast app-switch never leaves
        // a window stranded off-base.
        finish()

        let app = AXUIElementCreateApplication(pid)
        guard let w = axWindow(in: app, matching: wid) else { return }

        // Skip windows AX won't let us move (immovable / lazy-AX).
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
                w, kAXPositionAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let p0 = position(of: w)
        else { return }

        win = w
        origin = p0
        startUptime = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.debug(String(format: "shake FIRE pid=%d origin=(%.0f,%.0f) amp=%.0f dur=%.0fms",
                         pid, p0.x, p0.y, amplitude, durationMs))
    }

    private func tick() {
        guard let w = win else { return }
        // Bail if a mouse button went down mid-shake (the user grabbed the
        // window while it was still jiggling, e.g. keyboard-focus then drag
        // within the ~250ms window): snap back to origin and hand the frame
        // to the OS's cursor-track so the drag doesn't fight the sine.
        guard NSEvent.pressedMouseButtons == 0 else { finish(); return }
        let elapsedMs = (ProcessInfo.processInfo.systemUptime - startUptime) * 1000
        let p = elapsedMs / durationMs
        if p >= 1 { finish(); return }            // restores exact origin
        let env = (1 - CGFloat(p))
        let offset = amplitude * sin(2 * .pi * cycles * CGFloat(p)) * env
        setPosition(w, CGPoint(x: origin.x + offset, y: origin.y))
    }

    /// Stop the animation and restore the window to its exact origin.
    /// Safe to call when idle (no-op).
    func finish() {
        timer?.invalidate()
        timer = nil
        if let w = win { setPosition(w, origin) }
        win = nil
    }

    // MARK: - AX window resolution + position get/set

    /// The app's AX window matching the resolved CGWindowID, so the shake
    /// hits the SAME window the ring/flash chose — not whatever the app
    /// reports as `kAXFocusedWindow` (which can differ in multi-window
    /// apps). Falls back to the focused window when the id lookup can't
    /// match, rather than no-op'ing.
    private func axWindow(in app: AXUIElement, matching wid: CGWindowID) -> AXUIElement? {
        var ref: CFTypeRef?
        if let getWid = axGetWindow,
           AXUIElementCopyAttributeValue(
               app, kAXWindowsAttribute as CFString, &ref) == .success,
           let wins = ref as? [AXUIElement],
           let match = wins.first(where: {
               var id: CGWindowID = 0
               return getWid($0, &id) == .success && id == wid
           }) {
            return match
        }
        var fref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                app, kAXFocusedWindowAttribute as CFString, &fref) == .success,
              let raw = fref else { return nil }
        return (raw as! AXUIElement)   // kAXFocusedWindow is always an AXUIElement
    }

    private func position(of win: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                win, kAXPositionAttribute as CFString, &ref) == .success
        else { return nil }
        var pt = CGPoint.zero
        AXValueGetValue(ref as! AXValue, .cgPoint, &pt)
        return pt
    }

    @discardableResult
    private func setPosition(_ win: AXUIElement, _ pt: CGPoint) -> Bool {
        var p = pt
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(
            win, kAXPositionAttribute as CFString, v) == .success
    }
}
