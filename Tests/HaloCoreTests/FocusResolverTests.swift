import XCTest
@testable import HaloCore

/// The resolve reads z-order: the first front-to-back row that is not
/// halo's own, not excluded and not tiny wins; nothing sorts afterwards.
final class FocusResolverTests: XCTestCase {

    private func w(_ id: UInt32, pid: Int32, _ size: CGFloat = 400) -> WindowSnapshot {
        WindowSnapshot(id: id, ownerPID: pid, bounds: CGRect(x: 10, y: 20, width: size, height: size))
    }

    func testFirstMatchWinsInGivenOrder() {
        let pick = FocusResolver.focused(in: [w(1, pid: 100), w(2, pid: 200)],
                                         selfPID: 1, minSize: 80, isExcluded: { _ in false })
        XCTAssertEqual(pick?.id, 1)
    }

    func testSkipsSelfExcludedAndTiny() {
        let rows = [w(1, pid: 42), w(2, pid: 7), w(3, pid: 9, 79), w(4, pid: 9, 80)]
        let pick = FocusResolver.focused(in: rows, selfPID: 42, minSize: 80,
                                         isExcluded: { $0 == 7 })
        XCTAssertEqual(pick?.id, 4)
    }

    func testMinSizeAppliesToBothAxes() {
        let wide = WindowSnapshot(id: 1, ownerPID: 5, bounds: CGRect(x: 0, y: 0, width: 500, height: 30))
        XCTAssertNil(FocusResolver.focused(in: [wide], selfPID: 1, minSize: 80, isExcluded: { _ in false }))
    }

    func testEmptyIsNil() {
        XCTAssertNil(FocusResolver.focused(in: [], selfPID: 1, minSize: 80, isExcluded: { _ in false }))
    }

    func testExclusionIsOnlyAskedForOtherwiseEligibleRows() {
        var asked: [Int32] = []
        _ = FocusResolver.focused(in: [w(1, pid: 42), w(2, pid: 3, 10), w(3, pid: 8)],
                                  selfPID: 42, minSize: 80,
                                  isExcluded: { asked.append($0); return false })
        XCTAssertEqual(asked, [8])
    }
}
