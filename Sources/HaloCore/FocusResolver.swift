import CoreGraphics

/// One on-screen window as the resolve sees it. The app builds these from
/// the layer-0 rows of `CGWindowListCopyWindowInfo`, preserving its
/// front-to-back order — the order IS the focus signal.
public struct WindowSnapshot: Sendable, Equatable {
    public var id: UInt32
    public var ownerPID: Int32
    /// CG coordinates (y-down, origin top-left of the main display).
    public var bounds: CGRect

    public init(id: UInt32, ownerPID: Int32, bounds: CGRect) {
        self.id = id
        self.ownerPID = ownerPID
        self.bounds = bounds
    }
}

/// Picks which window the ring should be on. halo never asks the system
/// "what is focused"; it reads z-order.
public enum FocusResolver {
    /// Frontmost window in `windows` that is not owned by `selfPID`, not
    /// excluded, and at least `minSize` on both axes; nil when none.
    /// `isExcluded` is consulted per candidate (the app resolves the pid's
    /// bundle id lazily, so the common no-exclusion case costs nothing).
    public static func focused(in windows: [WindowSnapshot], selfPID: Int32,
                               minSize: CGFloat,
                               isExcluded: (Int32) -> Bool) -> WindowSnapshot? {
        windows.first { w in
            w.ownerPID != selfPID
                && w.bounds.width >= minSize && w.bounds.height >= minSize
                && !isExcluded(w.ownerPID)
        }
    }
}
