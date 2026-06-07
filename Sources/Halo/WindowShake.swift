import AppKit
import ApplicationServices

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

    /// Accessibility granted? (Required to move another app's window.)
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shake the focused window of app `pid`. No-op without AX trust,
    /// or when the app won't surface a movable focused window.
    func fire(pid: pid_t) {
        guard AXIsProcessTrusted() else { return }

        // Re-entrancy: snap any in-flight shake back to its origin
        // before starting the next, so a fast app-switch never leaves
        // a window stranded off-base.
        finish()

        let app = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let raw = winRef
        else { return }
        // kAXFocusedWindowAttribute always returns an AXUIElement.
        let w = raw as! AXUIElement

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

    // MARK: - AX position get/set

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
