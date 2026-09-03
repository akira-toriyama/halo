import XCTest
@testable import HaloCore

/// `[exclude].apps` grammar: anchored, case-insensitive, `*` / `?` only —
/// every other character is literal (a `.` in a bundle id is a dot).
final class GlobMatchTests: XCTestCase {

    func testExactIsAnchoredAndCaseInsensitive() {
        XCTAssertTrue(globMatch("com.apple.finder", "com.apple.Finder"))
        XCTAssertFalse(globMatch("com.apple.finder", "com.apple.finder.helper"))
        XCTAssertFalse(globMatch("apple.finder", "com.apple.finder"))
    }

    func testStarAndQuestionMark() {
        XCTAssertTrue(globMatch("*chrome*", "com.google.Chrome"))
        XCTAssertTrue(globMatch("com.apple.?inder", "com.apple.finder"))
        XCTAssertFalse(globMatch("com.apple.?inder", "com.apple.fiinder"))
        XCTAssertTrue(globMatch("*", ""))
    }

    func testRegexMetacharactersAreLiteral() {
        XCTAssertFalse(globMatch("com.apple.finder", "comXappleXfinder"))
        XCTAssertTrue(globMatch("a+b(c)", "A+B(C)"))
        XCTAssertFalse(globMatch("a+b", "aab"))
    }
}
