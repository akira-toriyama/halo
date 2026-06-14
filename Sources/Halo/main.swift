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

// `--emit-schema` is a one-shot: print the `config.toml` JSON Schema
// (Draft-07) to stdout and exit. Generated from the same declarative
// `configSpec` that decodes the config, so the two can't drift. The repo
// regenerates `config.schema.json` with `halo --emit-schema > config.schema.json`.
if CommandLine.arguments.dropFirst().contains("--emit-schema") {
    print(HaloConfig.jsonSchema, terminator: "")
    exit(0)
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
