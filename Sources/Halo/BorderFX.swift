// Neon-border animator — halo's LOCAL ring animation engine. Holds the
// border config + live animation state (rainbow hue cycle, width breath,
// focus flash) and drives one 30 Hz timer; the ring view renders the
// current `color` / `width` / `glow` in its `draw(_:)` by reading these
// values. The owner supplies `onRepaint` (→ needsDisplay).
//
// The effect PALETTES (neon/cyber/vapor/kawaii/rainbow/chomp) + the pure
// `blendThrough` cycle come from sill's `Effects` (`EffectSpec`), shared
// across the family — halo no longer hand-copies them from facet. The
// animator itself (timer, breathing, flash sequencing, `baseColor`
// fallback) is halo-specific motion and stays local. facet's "off"
// fallback was `pal.accent`; halo has no panel palette, so it falls back
// to a configurable `baseColor` instead.
//
// Not @MainActor (unlike facet's): halo is single-threaded on the main
// run loop, so the isolation just propagates friction with no safety gain.

import AppKit
import Effects

// (EffectSpec's pure UInt32 hexes materialize through sill 0.6's
// `NSColor(_ hex: HexColor)` Effects bridge — the local extension this
// file used to carry is retired.)

final class BorderFX {
    // Config (from the border config).
    private var fx: EffectSpec?
    private var glowOn = false
    private var baseW: CGFloat = 3
    private var cycleSeconds: CGFloat = 6
    private var minW: CGFloat?
    private var maxW: CGFloat?
    private var cycleColors = false
    /// Keep the repaint timer running continuously (line-pets orbit the
    /// ring forever while a window is focused — they're driven by
    /// wall-clock time in RingView, so they just need steady redraws).
    private var petsActive = false
    /// Resting color when no effect is active ("off").
    var baseColor: NSColor = .systemTeal

    // NSColors resolved from `fx` once at configure — `EffectSpec` is pure
    // UInt32 hex, the ring draws `NSColor`, so convert at the seam.
    private var steadyColor: NSColor = .systemTeal
    private var flashColors: [NSColor] = []

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
                   minWidth: CGFloat?, maxWidth: CGFloat?, baseColor bc: NSColor,
                   hasPets: Bool) {
        fx = borderEffectFor(effectName)                  // sill's catalog → EffectSpec?
        steadyColor = fx.map { NSColor(HexColor($0.steady)) } ?? bc
        flashColors = fx?.flash.map { NSColor(HexColor($0)) } ?? []
        glowOn = glow
        baseW = width
        cycleSeconds = max(1, cs)
        cycleColors = cc
        minW = minWidth
        maxW = maxWidth
        baseColor = bc
        petsActive = hasPets
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
        if cycleColors, !fx.flash.isEmpty {
            let c = blendThrough(fx.flash, at: Double(cyclePhase))   // sill's pure cycle
            return NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
        }
        return steadyColor
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
        flashSeq = idxs.map { flashColors[$0] }
        flashStep = 0
        updateTimer()
        onRepaint?()
    }

    func stop() { stopTimer() }

    private func updateTimer() {
        if (fx != nil && cyclingOrBreathing) || flashing || petsActive { startTimer() } else { stopTimer() }
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
        if !flashing && !(fx != nil && cyclingOrBreathing) && !petsActive { stopTimer() }
    }
}
