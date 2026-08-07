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
    ],
    dependencies: [
        // sill — the swift app family's shared theming library. halo
        // consumes ONLY the dynamic `Effects` atom: the border-effect
        // catalog (neon/cyber/vapor/kawaii/rainbow/chomp), the pure
        // `blendThrough` cycle, and the shared `LinePet` / `drawLinePets`
        // (orbiting pets) — replacing the BorderEffect palettes it used to
        // hand-copy from facet. No PaletteKit: halo draws only a ring, so
        // it needs the effect DATA, not a resolved text/bg theme palette.
        // Since 0.6.0 Effects `@_exported import`s Palette, so the pure
        // vocabulary (canonicalLinePetNames, parseColorToken, HexColor)
        // and the `NSColor(_ hex: HexColor)` bridge arrive with no extra
        // product link.
        //
        // Swap to `.package(path: "../sill")` for atomic local sill+halo
        // editing during dev; the committed form pins the published tag.
        // Floor 5.0.0 — halo sat on 0.11.0 for six weeks and was the family's
        // most-behind consumer by four majors. The jump crosses sill 1.x→5.x,
        // but halo links only `Effects` (+ the `Palette` vocabulary it
        // re-exports) and `ConfigSchema`, and NONE of sill's majors touched
        // those: v2.0.0 raised the macOS floor (applied above), v3/v4 reshaped
        // ThemeKitUI + typed the theme catalog, v5.0.0 made themed SwiftUI
        // widgets ambient. Measured, not assumed — `swift build` is clean with
        // zero source changes, and `halo --emit-schema` differs from the
        // committed schema only by the ten themes sill added meanwhile.
        // `ConfigSchema` still drives BOTH the config.toml decode AND the JSON
        // Schema emitted for taplo completion (`halo --emit-schema`).
        .package(url: "https://github.com/akira-toriyama/sill", .upToNextMinor(from: "6.0.0")),
        // swift-toml-edit — the family's ONE TOML implementation (Sill-1).
        // Provides the `Toml` module halo reads config with (`Toml.parseFlat`);
        // the module name is unchanged so `import Toml` survives. In its own
        // repo since sill 0.11.0. Floor 2.3.1 and `.upToNextMajor` to match the
        // rest of the family (chord/facet/perch/wand all pin 2.x this way);
        // halo and glance were the last two consumers left on 1.x.
        .package(url: "https://github.com/akira-toriyama/swift-toml-edit", .upToNextMajor(from: "2.3.1")),
    ],
    targets: [
        .executableTarget(
            name: "Halo",
            dependencies: [
                .product(name: "Effects", package: "sill"),
                // Toml: the family's pure config parser (`Toml.parseFlat`),
                // now sourced from the standalone swift-toml-edit package.
                .product(name: "Toml", package: "swift-toml-edit"),
                // ConfigSchema: one declarative `Spec` drives BOTH the
                // config.toml decode and the JSON Schema emitted for taplo
                // completion (`halo --emit-schema`) — so the two never drift.
                .product(name: "ConfigSchema", package: "sill"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // Drift guard: the committed config.schema.json must equal the live
        // `configSpec.jsonSchema()` — so the editor schema can never drift
        // from the parser. CLT ships no XCTest, so this runs in CI (the
        // shared swift-build action's `swift test` step).
        .testTarget(
            name: "HaloTests",
            dependencies: ["Halo"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
