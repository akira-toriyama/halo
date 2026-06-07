// Neon-border animator — ported from facet's FacetView/BorderFX.swift.
// Holds the border config + live animation state (rainbow hue cycle,
// width breath, focus flash) and drives one 30 Hz timer; the ring view
// renders the current `color` / `width` / `glow` in its `draw(_:)` by
// reading these values. The owner supplies `onRepaint` (→ needsDisplay).
//
// Only change from facet: facet's "off" fallback was `pal.accent` (the
// panel theme accent); halo has no panel palette, so it falls back to a
// configurable `baseColor` instead.

import AppKit

// Not @MainActor (unlike facet's): halo is single-threaded on the main
// run loop, so the isolation just propagates friction with no safety gain.
final class BorderFX {
    // Config (from the border config).
    private var fx: BorderEffect?
    private var glowOn = false
    private var baseW: CGFloat = 3
    private var cycleSeconds: CGFloat = 6
    private var minW: CGFloat?
    private var maxW: CGFloat?
    private var cycleColors = false
    /// Resting color when no effect is active ("off").
    var baseColor: NSColor = .systemTeal

    // Live animation state.
    private var cyclePhase: CGFloat = 0
    private var flashSeq: [NSColor] = []
    private var flashStep = -1
    private var timer: Timer?

    /// Repaint hook — set the owner's `needsDisplay = true`.
    var onRepaint: (() -> Void)?

    init() {}

    func configure(effectName: String, glow: Bool, width: CGFloat,
                   cycleSeconds cs: CGFloat, cycleColors cc: Bool,
                   minWidth: CGFloat?, maxWidth: CGFloat?, baseColor bc: NSColor) {
        fx = borderEffectFor(effectName)
        glowOn = glow
        baseW = width
        cycleSeconds = max(1, cs)
        cycleColors = cc
        minW = minWidth
        maxW = maxWidth
        baseColor = bc
        updateTimer()
        onRepaint?()
    }

    var active: Bool { fx != nil }
    var glowEnabled: Bool { glowOn }
    private var flashing: Bool { flashStep >= 0 && flashStep < flashSeq.count }

    private var breathing: Bool {
        guard fx != nil, let lo = minW, let hi = maxW else { return false }
        return hi > lo
    }
    private var cyclingOrBreathing: Bool {
        (fx?.cycles ?? false) || (cycleColors && fx != nil) || breathing
    }

    /// Current border color: flash blink → rotating rainbow hue → cycling
    /// flash palette → the effect's steady color → `baseColor` when off.
    var color: NSColor {
        if flashing { return flashSeq[flashStep] }
        guard let fx else { return baseColor }
        if fx.cycles { return NSColor(hue: cyclePhase, saturation: 0.9, brightness: 1, alpha: 1) }
        if cycleColors, !fx.flash.isEmpty { return blendThrough(fx.flash, at: cyclePhase) }
        return fx.steady
    }

    /// Current width: breathing min↔max (raised cosine) or fixed, +1.5 on flash.
    var width: CGFloat {
        var w = baseW
        if breathing, let lo = minW, let hi = maxW {
            let pulse = (1 - CGFloat(cos(2 * Double.pi * Double(cyclePhase)))) / 2
            w = lo + (hi - lo) * pulse
        }
        return flashing ? w + 1.5 : w
    }

    /// Start a focus flash: a 5-blink burst through the effect's palette.
    /// No-op when off / palette-less (then the ring just re-hugs silently).
    func flash() {
        guard let fx, !fx.flash.isEmpty else { return }
        var idxs: [Int] = []
        var last = -1
        for _ in 0..<5 {
            var i = Int.random(in: 0..<fx.flash.count)
            if fx.flash.count > 1 { while i == last { i = Int.random(in: 0..<fx.flash.count) } }
            idxs.append(i); last = i
        }
        flashSeq = idxs.map { fx.flash[$0] }
        flashStep = 0
        updateTimer()
        onRepaint?()
    }

    func stop() { stopTimer() }

    private func updateTimer() {
        if (fx != nil && cyclingOrBreathing) || flashing { startTimer() } else { stopTimer() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func tick() {
        if flashing {
            flashStep += 1
            if flashStep >= flashSeq.count { flashStep = -1 }
        }
        if fx != nil && cyclingOrBreathing {
            cyclePhase += (1.0 / 30.0) / cycleSeconds
            if cyclePhase >= 1 { cyclePhase -= 1 }
        }
        onRepaint?()
        if !flashing && !(fx != nil && cyclingOrBreathing) { stopTimer() }
    }
}
