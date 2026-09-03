import XCTest
@testable import HaloCore

/// One lap per `pet-lap-seconds` regardless of window size.
final class PetOrbitTests: XCTestCase {

    func testSpeedIsPerimeterOverLap() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)   // perimeter 1000
        XCTAssertEqual(PetOrbit.speed(around: rect, lapSeconds: 8), 125)
        XCTAssertEqual(PetOrbit.speed(around: rect.insetBy(dx: -100, dy: -100), lapSeconds: 8), 225)   // 500×400 → 1800
    }

    func testLapFloorsAtHalfASecond() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)   // perimeter 400
        XCTAssertEqual(PetOrbit.speed(around: rect, lapSeconds: 0), 800)
        XCTAssertEqual(PetOrbit.speed(around: rect, lapSeconds: 0.5), 800)
    }
}
