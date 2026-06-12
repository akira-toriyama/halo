import AppKit

// Focus-sound — plays a short audio cue when focus changes to a
// different window. A sibling-repo "satellite" alongside the ring, the
// focus flash, and the shake: the third focus-change feedback modality
// (visual flash, physical jiggle, now an audible cue). Reimplements an
// older `window_focused → afplay` hook directly inside halo.
//
// User-supplied file, OFF by default: point `sound` at an audio path in
// config and it plays at `sound-volume`; leave it empty and halo stays
// silent. halo ships no sound of its own (no bundled asset — stays lean,
// like the ring carries no panel theme). Needs NO permission — audio
// playback is unrestricted with SIP on, so this never touches the
// Accessibility gate that the shake needs.
//
// Latest-wins on rapid focus changes: each play() restarts the in-flight
// sound, so an alt-tab burst never stacks into noise — only the newest
// window's cue is heard. NSSound (in-process) over `afplay` (a process
// per focus) so a long-running agent spawns nothing and the file is
// decoded once.
//
// Not @MainActor: like the rest of halo, single-threaded on the main run
// loop. configure() / play() are called from BorderController on main.
final class FocusSound {
    private var sound: NSSound?
    private var loadedPath: String?     // the expanded path currently decoded

    /// Configure from the config file path (`~` expanded) + volume.
    /// Empty path → off. Re-decodes the file only when the path changes,
    /// so an unrelated hot-reload edit doesn't reload the audio.
    func configure(path: String, volume: Double) {
        let expanded = path.isEmpty ? "" : (path as NSString).expandingTildeInPath
        if expanded != loadedPath {
            sound?.stop()
            sound = expanded.isEmpty ? nil
                : NSSound(contentsOfFile: expanded, byReference: false)
            loadedPath = expanded
            if !expanded.isEmpty && sound == nil {
                Log.line("sound file not loadable (ignored): \(expanded)")
            }
        }
        sound?.volume = Float(max(0, min(1, volume)))
    }

    /// Play the focus cue. Latest-wins: restart if already sounding so a
    /// fast focus burst never overlaps. No-op when no sound is configured.
    func play() {
        guard let s = sound else { return }
        if s.isPlaying { s.stop() }     // play() alone won't restart a live sound
        s.play()
    }
}
