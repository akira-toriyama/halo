import Palette
import XCTest
@testable import HaloCore

/// `HaloConfig.parse` — the clamp-to-default policy per field kind, pinned
/// so a Spec edit cannot silently change what a typo does to the ring.
final class ConfigDecodeTests: XCTestCase {

    func testEmptyAndUnknownKeysKeepDefaults() {
        let d = HaloConfig()
        let c = HaloConfig.parse("[border]\nnonsense = 1\n[nope]\nx = 2\n")
        XCTAssertEqual(c.effect, d.effect)
        XCTAssertEqual(c.width, d.width)
        XCTAssertEqual(c.color, d.color)
        XCTAssertEqual(c.shake, d.shake)
    }

    func testEffectIsLowercasedAndUnknownKeepsDefault() {
        XCTAssertEqual(HaloConfig.parse("[border]\neffect = \"RAINBOW\"\n").effect, "rainbow")
        XCTAssertEqual(HaloConfig.parse("[border]\neffect = \"neonish\"\n").effect, "neon")
    }

    func testColorCycleMsFloorsAt100AndStoresSeconds() {
        XCTAssertEqual(HaloConfig.parse("[border]\ncolor-cycle-ms = 2500\n").cycleSeconds, 2.5)
        XCTAssertEqual(HaloConfig.parse("[border]\ncolor-cycle-ms = 5\n").cycleSeconds, 0.1)
    }

    func testColorParsesSillGrammarAndStaysHex() {
        XCTAssertEqual(HaloConfig.parse("[border]\ncolor = \"#ff0000\"\n").color, HexColor(0xFF0000))
        XCTAssertEqual(HaloConfig.parse("[border]\ncolor = \"not a color\"\n").color, HexColor(0x39C5C8))
    }

    func testSoundVolumeClampsToUnit() {
        XCTAssertEqual(HaloConfig.parse("[sound]\nsound-volume = 7\n").soundVolume, 1)
        XCTAssertEqual(HaloConfig.parse("[sound]\nsound-volume = -1\n").soundVolume, 0)
    }

    func testSchemaMinIsARuntimeClampForEveryNumberField() {
        let c = HaloConfig.parse("""
            [border]
            width = -5
            corner-radius = -1
            pad = -2
            min-size = -80
            min-width = -3
            [shake]
            shake-amplitude = -10
            """)
        XCTAssertEqual(c.width, 0)
        XCTAssertEqual(c.cornerRadius, 0)
        XCTAssertEqual(c.pad, 0)
        XCTAssertEqual(c.minSize, 0)
        XCTAssertEqual(c.shakeAmplitude, 0)
        XCTAssertEqual(c.minWidth, -3)        // the breathing bounds declare no schema min
        XCTAssertEqual(HaloConfig.parse("[border]\nwidth = 2.5\n").width, 2.5)
    }

    func testShakeDurationAndPetFloors() {
        XCTAssertEqual(HaloConfig.parse("[shake]\nshake-duration-ms = 0\n").shakeDurationMs, 1)
        XCTAssertEqual(HaloConfig.parse("[pets]\npet-scale = 0\n").petScale, 0.1)
        XCTAssertEqual(HaloConfig.parse("[pets]\npet-lap-seconds = 0.01\n").petLapSeconds, 0.5)
    }

    func testLinePetsLowercaseAndDropUnknown() {
        let c = HaloConfig.parse("[pets]\nline-pets = [\"Chomp\", \"dragon\", \" ghost \"]\n")
        XCTAssertEqual(c.linePets, [.chomp, .ghost])
    }

    func testExcludedAppsGlobThroughIsExcluded() {
        let c = HaloConfig.parse("[exclude]\napps = [\"com.apple.finder\", \"*chrome*\"]\n")
        XCTAssertTrue(c.isExcluded(bundleID: "com.google.Chrome"))
        XCTAssertFalse(c.isExcluded(bundleID: "com.apple.Safari"))
        XCTAssertFalse(HaloConfig().isExcluded(bundleID: "com.apple.finder"))
    }
}
