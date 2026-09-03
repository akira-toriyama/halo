// swift-tools-version:6.0
//
// halo — active-window border for macOS.
//
// A focused, standalone tool in the facet family: draws a neon ring
// around the currently-focused window, follows it smoothly as you drag
// it (private-SkyLight window-server events at ~5ms), and flashes on
// focus change. Pairs with facet but depends on nothing from it — a
// separate sibling repo, per facet's "adjacent features → sibling
// repos" decision (2026-06-05): the border is facet-adjacent but not
// core window management, so it lives on its own and keeps facet's core
// minimal.
//
//   HaloCore   pure logic: config decode + schema (ConfigSchema), the
//              focus resolve over window snapshots, overlay ↔ ring
//              geometry, the shake curve, pet orbit speed, Log. No
//              AppKit, no SkyLight, no AX. Fully testable.
//
//   Halo       executable: @main, the private-SkyLight event seam, the
//              overlay window + ring view, BorderFX (NSColor
//              materialization over sill's clockless resolve), the AX
//              focus-shake, the focus-sound. The ONLY module that
//              imports AppKit.
//
// Tests live under Tests/HaloCoreTests.
//
// The whole tool is single-threaded on the main run loop plus a handful
// of private-SkyLight C callbacks, so the executable target uses Swift 5
// language mode: strict concurrency would add ceremony here with no
// safety gain (no cross-thread shared mutable state — the SkyLight
// callbacks are serviced on the main run loop).

import PackageDescription

let package = Package(
    name: "halo",
    // macOS-26 floor, inherited from sill. sill v2.0.0 raised its own floor to
    // 26 for the SwiftUI migration, so any consumer that steps past sill 1.x
    // adopts it too — this is that step (family policy t-tbar D2 / t-fs7p).
    // Spelled as a string because `.v26` does not exist in this toolchain's
    // PackageDescription.
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "halo", targets: ["Halo"]),
        .library(name: "HaloCore", targets: ["HaloCore"]),
    ],
    dependencies: [
        // sill — the swift app family's shared theming library. The app
        // consumes the dynamic `Effects` atom: the border-effect catalog
        // (neon/cyber/vapor/kawaii/rainbow/chomp), the clockless
        // `resolveBorder`, and the shared `drawLinePets` (orbiting pets).
        // HaloCore links only the pure `Palette` vocabulary
        // (canonicalEffectNames / canonicalLinePetNames, parseColorToken,
        // HexColor, LinePet) — Effects imports AppKit, so it stays out of
        // Core. No PaletteKit: halo draws only a ring, so it needs the
        // effect DATA, not a resolved text/bg theme palette.
        //
        // Swap to `.package(path: "../sill")` for atomic local sill+halo
        // editing during dev; the committed form pins the published tag.
        // `.upToNextMinor` off the current major, the same pin shape as the
        // rest of the family; dependabot proposes the bumps. `ConfigSchema`
        // drives BOTH the config.toml decode AND the JSON Schema emitted for
        // taplo completion (`halo --emit-schema`).
        .package(url: "https://github.com/akira-toriyama/sill", .upToNextMinor(from: "8.0.0")),
        // swift-toml-edit — the family's ONE TOML implementation (Sill-1).
        // Provides the `Toml` module halo reads config with (`Toml.parseFlat`);
        // the module name is unchanged so `import Toml` survives. In its own
        // repo since sill 0.11.0. Floor 2.3.1 and `.upToNextMajor` to match the
        // rest of the family (chord/facet/perch/wand all pin 2.x this way);
        // halo and glance were the last two consumers left on 1.x.
        .package(url: "https://github.com/akira-toriyama/swift-toml-edit", .upToNextMajor(from: "2.3.1")),
    ],
    targets: [
        .target(
            name: "HaloCore",
            dependencies: [
                .product(name: "Palette", package: "sill"),
                // Toml: the family's pure config parser (`Toml.parseFlat`).
                .product(name: "Toml", package: "swift-toml-edit"),
                // ConfigSchema: one declarative `Spec` drives BOTH the
                // config.toml decode and the JSON Schema emitted for taplo
                // completion (`halo --emit-schema`) — so the two never drift.
                .product(name: "ConfigSchema", package: "sill"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Halo",
            dependencies: [
                "HaloCore",
                .product(name: "Effects", package: "sill"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // Pure-logic tests, plus the drift guard: the committed
        // config.schema.json must equal the live `configSpec.jsonSchema()`.
        // CLT ships no XCTest, so these run in CI (the shared swift-build
        // action's `swift test` step).
        .testTarget(
            name: "HaloCoreTests",
            dependencies: [
                "HaloCore",
                .product(name: "Palette", package: "sill"),
                .product(name: "ConfigSchema", package: "sill"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
