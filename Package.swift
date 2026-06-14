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
    platforms: [.macOS(.v13)],
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
        // Floor 0.9.0 = the `ConfigSchema` module (one declarative `Spec`
        // drives BOTH the config.toml decode AND the JSON Schema emitted for
        // taplo completion — `halo --emit-schema`). 0.9.0 is an additive
        // superset, so the existing Effects/Palette usage is unaffected.
        .package(url: "https://github.com/akira-toriyama/sill", .upToNextMinor(from: "0.9.0")),
    ],
    targets: [
        .executableTarget(
            name: "Halo",
            dependencies: [
                .product(name: "Effects", package: "sill"),
                // Toml: the family's pure config parser (`Toml.parseFlat`).
                .product(name: "Toml", package: "sill"),
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
