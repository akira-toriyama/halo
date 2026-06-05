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
    targets: [
        .executableTarget(
            name: "Halo",
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
