import AppKit

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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)        // LSUIElement: agent, no Dock icon
let delegate = HaloApp()
app.delegate = delegate
app.run()
