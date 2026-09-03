import ConfigSchema
import XCTest
@testable import HaloCore

/// `HaloConfig.validate` — the strict check `load` logs from. It reads the
/// SAME `configSpec` as the decode and the emitted schema, so what taplo
/// flags in the editor is what lands in /tmp/halo.log on a hot-reload.
final class ConfigValidateTests: XCTestCase {

    func testCommittedTemplateIsClean() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/HaloCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // <repo root>
        let text = try String(contentsOf: repoRoot.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(try HaloConfig.validate(text), [])
        XCTAssertEqual(HaloConfig.warnSchemaViolations(text), 0)
    }

    func testRangeEnumTypeAndUnknownKeyAreReported() throws {
        let errors = try HaloConfig.validate("""
            [border]
            width = -5
            effect = "neonish"
            glow = "yes"
            wdith = 3
            """)
        XCTAssertEqual(errors.count, 4, errors.map(\.message).joined(separator: "\n"))
        let paths = Set(errors.map(\.pathString))
        XCTAssertEqual(paths, ["border.width", "border.effect", "border.glow", "border.wdith"])
        XCTAssertTrue(errors.contains { if case .outOfRange = $0.rule { return true } else { return false } })
        XCTAssertTrue(errors.contains { if case .notInEnum = $0.rule { return true } else { return false } })
        XCTAssertTrue(errors.contains { if case .typeMismatch = $0.rule { return true } else { return false } })
        XCTAssertTrue(errors.contains { if case .unknownKey = $0.rule { return true } else { return false } })
    }

    func testSyntaxErrorThrowsButLoadPathWarnsZero() {
        let broken = "[border\nwidth = 3\n"
        XCTAssertThrowsError(try HaloConfig.validate(broken))
        XCTAssertEqual(HaloConfig.warnSchemaViolations(broken), 0)
    }

    /// The classic typo — an unquoted string — makes the strict parser
    /// refuse the whole file. The load path must still report the OTHER
    /// keys' violations (over what the lenient scanner read), not go quiet.
    func testStrictRejectionStillValidatesWhatTheScannerRead() {
        let typo = "[border]\neffect = rainbow\nwidth = -5\n[sound]\nsound-volume = 7\n"
        XCTAssertThrowsError(try HaloConfig.validate(typo))
        XCTAssertEqual(HaloConfig.warnSchemaViolations(typo), 2)   // border.width + sound.sound-volume
        let c = HaloConfig.parse(typo)
        XCTAssertEqual(c.effect, "neon")     // the bad line is dropped, default kept
        XCTAssertEqual(c.width, 0)           // clamped
        XCTAssertEqual(c.soundVolume, 1)
    }

    func testWarnCountsEveryViolation() {
        XCTAssertEqual(HaloConfig.warnSchemaViolations("[sound]\nsound-volume = 7\n[pets]\npet-scale = \"big\"\n"), 2)
    }
}
