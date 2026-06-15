import AppKit
import ApplicationServices

// halo — active-window border. Entry point + lifecycle.
//
// An LSUIElement agent (no Dock icon, never steals focus). It opens a
// dedicated window-event connection, then keeps a transparent ring hugged
// to whatever window is frontmost.
final class HaloApp: NSObject, NSApplicationDelegate {
    private let config = HaloConfig.load()
    private let events = WindowServerEvents()
    private var border: BorderController!
    private var safetyNet: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.line("halo up (verbose=\(Log.enabled))")

        // The ring itself is read-only, but focus-shake MOVES the focused
        // window via AX, which needs Accessibility. Prompt only when the
        // feature is on — `shake = false` keeps halo permission-free.
        if config.shake,
           !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            Log.line("focus-shake needs Accessibility — grant halo in System Settings → "
                + "Privacy & Security → Accessibility, then restart (or set shake = false)")
        }

        border = BorderController(config: config, events: events)
        events.onEvent = { [weak self] event in self?.border.onEvent(event) }

        guard events.start() else {
            Log.line("‼️ could not start the window-event seam — exiting")
            NSApp.terminate(nil); return
        }
        border.poll()

        // Safety net (yabai-style): periodically re-subscribe the on-screen
        // set + re-hug, so windows opened after launch start emitting
        // MOVE/RESIZE and a missed event can't leave the ring stale. The
        // live, smooth tracking still comes from the ~5ms events.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.border.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyNet = timer
    }
}

// CLI surface. halo is config-driven — `~/.config/halo/config.toml`
// (hot-reloaded on save) is the entire control plane; there is no runtime
// control CLI (atelier Phase 3 classifies halo OUT of the domain-verb
// grammar — inventing a control CLI would be a feature, not a refactor).
// The only recognised flags are `--emit-schema` and the family `-h`/`--help`
// carve-out. ANY other argument is rejected loudly with exit 2 (the family
// "no silent fallback" sub-rule) instead of being silently ignored while
// halo launches anyway. A normal agent launch (`open Halo.app`, brew
// services, LaunchAgent) passes no argv, so this never blocks startup.
let cliArgs = Array(CommandLine.arguments.dropFirst())

if cliArgs.contains("--help") || cliArgs.contains("-h") {
    print("""
    halo — active-window border for macOS.

    USAGE
      halo                  run as agent (config-driven; no runtime CLI)
      halo --emit-schema    print the config.toml JSON Schema (Draft-07)
      halo --help, -h       this help

    EXIT CODES
      0   success
      2   unknown argument (loud on stderr)

    CONFIG
      ~/.config/halo/config.toml is the single source of truth, hot-reloaded
      on save. halo has no control flags — every knob lives in the file.

    DOCS
      https://github.com/akira-toriyama/halo
    """)
    exit(0)
}

// `--emit-schema` is a one-shot: print the `config.toml` JSON Schema
// (Draft-07) to stdout and exit. Generated from the same declarative
// `configSpec` that decodes the config, so the two can't drift. The repo
// regenerates `config.schema.json` with `halo --emit-schema > config.schema.json`.
if cliArgs.contains("--emit-schema") {
    print(HaloConfig.jsonSchema, terminator: "")
    exit(0)
}

// Reject anything else loudly (no silent fallback). `--emit-schema` /
// `--help` / `-h` exited above, so any remaining token is unrecognised.
if let bad = cliArgs.first {
    FileHandle.standardError.write(Data((
        "halo: unknown argument \"\(bad)\" — halo is config-driven and has "
        + "no control CLI. See `halo --help`.\n"
    ).utf8))
    exit(2)
}

// Refresh the taplo schema sidecar next to the user config so editor
// completion/validation just works (idempotent; writes only on change,
// and the watcher polls config.toml's mtime not this sibling, so no
// hot-reload churn). Best-effort — never blocks start.
HaloConfig.installSchema()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)        // LSUIElement: agent, no Dock icon
let delegate = HaloApp()
app.delegate = delegate
app.run()
