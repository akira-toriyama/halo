import XCTest
@testable import HaloCore

/// The overlay is the hugged window + 2·glowPad per axis (capsule's
/// halo-hug driver gates on exactly +48/+48), flipped from CG to Cocoa.
final class RingGeometryTests: XCTestCase {

    func testOverlayFrameFlipsAndExpandsByGlowPad() {
        let cg = CGRect(x: 100, y: 50, width: 300, height: 200)
        let f = RingGeometry.overlayFrame(hugging: cg, screenHeight: 1000)
        XCTAssertEqual(f.width, 300 + 2 * RingGeometry.glowPad)
        XCTAssertEqual(f.height, 200 + 2 * RingGeometry.glowPad)
        XCTAssertEqual(RingGeometry.glowPad, 24)
        // Cocoa origin: y-up, so a window 50pt below the top of a 1000pt
        // screen has its bottom at 1000 - 50 - 200 = 750, minus the pad.
        XCTAssertEqual(f.origin.x, 100 - 24)
        XCTAssertEqual(f.origin.y, 750 - 24)
    }

    func testRingRectSitsPadOutsideTheWindowEdge() {
        let overlay = CGRect(x: 0, y: 0, width: 348, height: 248)   // a 300×200 window + 2·glowPad
        let ring = RingGeometry.ringRect(in: overlay, pad: 4)
        XCTAssertEqual(ring, CGRect(x: 20, y: 20, width: 308, height: 208))
        XCTAssertEqual(RingGeometry.ringRect(in: overlay, pad: 0),
                       overlay.insetBy(dx: 24, dy: 24))
    }
}
