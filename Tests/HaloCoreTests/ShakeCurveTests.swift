import XCTest
@testable import HaloCore

/// The envelope's two jobs: taper the swing, and land x(1) on the exact
/// origin so the final AX write never leaves the window off-base.
final class ShakeCurveTests: XCTestCase {

    func testEndsExactlyAtOrigin() {
        XCTAssertEqual(ShakeCurve.offset(progress: 1, amplitude: 10), 0)
        XCTAssertEqual(ShakeCurve.offset(progress: 1.7, amplitude: 10), 0)   // over-run clamps
        XCTAssertEqual(ShakeCurve.offset(progress: 0, amplitude: 10), 0)
    }

    func testStaysInsideTheDecayingEnvelope() {
        for i in 0...100 {
            let p = Double(i) / 100
            let bound = 10 * (1 - CGFloat(p))
            XCTAssertLessThanOrEqual(abs(ShakeCurve.offset(progress: p, amplitude: 10)), bound + 1e-9,
                                     "p=\(p)")
        }
    }

    func testActuallySwingsBothWays() {
        let samples = (1..<100).map { ShakeCurve.offset(progress: Double($0) / 100, amplitude: 10) }
        XCTAssertGreaterThan(samples.max()!, 5)
        XCTAssertLessThan(samples.min()!, -5)
    }
}
