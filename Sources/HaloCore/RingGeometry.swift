import CoreGraphics

/// The overlay ↔ ring geometry. Two rectangles, never the same one: the
/// overlay is the borderless window; the ring is the stroke drawn inside
/// it. The capsule acceptance driver (drivers/halo-hug.sh) gates on the
/// overlay being exactly the hugged window + 2·glowPad per axis, so this
/// arithmetic is a contract, not an implementation detail.
public enum RingGeometry {
    /// Margin by which the overlay is expanded beyond the window rect, so
    /// the glow can bloom OUTWARD past the window edge instead of being
    /// clipped. Headroom the user never sees and cannot set.
    public static let glowPad: CGFloat = 24

    /// Overlay frame for a window whose CG (y-down) bounds are `cg`, on a
    /// main display `screenHeight` tall: flipped to Cocoa (y-up), then
    /// expanded by `glowPad` on every side.
    public static func overlayFrame(hugging cg: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: cg.origin.x, y: screenHeight - cg.origin.y - cg.height,
               width: cg.width, height: cg.height)
            .insetBy(dx: -glowPad, dy: -glowPad)
    }

    /// The ring's rect inside the overlay: the window edge sits `glowPad`
    /// inside the overlay bounds and the ring sits `pad` outside the
    /// window edge.
    public static func ringRect(in overlayBounds: CGRect, pad: CGFloat) -> CGRect {
        overlayBounds.insetBy(dx: glowPad - pad, dy: glowPad - pad)
    }
}
