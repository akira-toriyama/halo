# halo — glossary

The vocabulary halo's code, its doc comments and its task bodies use as terms of
art. It exists to stop the reader and Claude Code from meaning two different
things by one word. halo is small (13 files, ~1,400 lines across two modules,
`HaloCore` and `Halo`) but almost every
word in it names a distinction that is expensive to collapse — *ring* vs
*overlay*, *pad* vs *glowPad*, *event* vs *poll*, *flash* vs *shake* vs *sound*,
*read-only* vs *moves the window* — and in each entry below the **distinction is
the content**. An entry that only restated the name would be worth nothing.

**Ordering: grouped by area, not alphabetical.** Nearly every term is meaningful
only next to its neighbours: *event seam → notify proc → drain pump → resolve →
hug* is one chain, and alphabetical order would shred it. Each term appears in
**bold** exactly once, so Ctrl-F on the word is as good as an index.

Each entry ends with where it lives: a file and a *symbol*, never a line number
(line numbers rot; this file was written at `0d0a393`). Paths are from the
repository root. Per the fleet
[doc-consistency policy](https://github.com/akira-toriyama/.github/blob/main/docs/doc-consistency-policy.md)
this file is English-only and code-first: where a definition and the code
disagree, the code wins and this file is the bug.

Maintaining it: a term is added or renamed in the **same PR** as the code change
that introduces or renames it, and when a cited symbol disappears its entry goes
with it. A glossary that documents a name the tree no longer has is worse than a
missing entry, because it is the one place a reader trusts not to be stale.

**Contents**

1. [The ring](#1-the-ring) — ring, overlay, hug, pad, glowPad, click-through, agent, desktop-local
2. [The event seam](#2-the-event-seam) — seam, dedicated connection, notify proc, drain pump, event port, per-window subscription, event code, safety-net poll, settle re-resolve
3. [Resolving focus](#3-resolving-focus) — resolve, snapshot, layer-0, front-to-back, exclusion, min-size, first resolve
4. [Focus feedback](#4-focus-feedback) — the three modalities, flash, focus-shake, focus-sound, latest-wins
5. [The shake in detail](#5-the-shake-in-detail) — read-only vs moves, AX trust, deferred shake, drag threshold, envelope, position-only, lazy-AX
6. [One clock](#6-one-clock) — the one clock, redraw heartbeat, clockless math, sample, animating, breathe, cycle, line-pets
7. [Config](#7-config) — config-driven, hot-reload, the spec, schema sidecar, clamp-to-default, glob, no silent fallback
8. [Boundaries](#8-boundaries) — satellite, what sill owns, what halo owns, Core vs App, mirror

---

## 1. The ring

**ring** — the rounded neon stroke halo draws around the focused window. The
thing the user sees. Distinguish from **overlay** — the borderless `NSWindow`
the ring is drawn *inside*. They are not the same rectangle, and conflating them
is the fastest way to get the geometry wrong (see *pad* / *glowPad*).
`Sources/Halo/Border.swift`, *RingView*.

**hug** — to move the overlay so it tracks the focused window's current frame.
Every MOVE / RESIZE event re-hugs; that is what makes the ring follow smoothly
during a drag rather than jumping after it. `Sources/Halo/Border.swift`,
*BorderController.update(trigger:resubscribe:)*.

**pad** — the user-configurable gap between the window edge and the ring
(default 4pt). Distinguish sharply from **glowPad** — a fixed 24pt margin by
which the *overlay* is expanded beyond the window rect, so the glow can bloom
OUTWARD past the window edge instead of being clipped. `pad` is a look;
`glowPad` is headroom the user never sees and cannot set. The ring's rect is
therefore the overlay bounds inset by `glowPad - pad`. Both rectangles are pure
arithmetic, and the capsule acceptance driver gates on the overlay being the
window + 2·`glowPad`. `Sources/HaloCore/RingGeometry.swift`, *RingGeometry*.

**click-through** — the overlay sets `ignoresMouseEvents`, so the ring is never a
target: clicks land on the window underneath. Together with never becoming key,
this is why the ring needs no permission at all.
`Sources/Halo/Border.swift`, *BorderController.init*.

**agent** — halo runs as an `LSUIElement` / `.accessory` app: no Dock icon, never
steals focus. Load-bearing for a focus-tracking tool — an app that took focus
would change the thing it is measuring. `Sources/Halo/HaloApp.swift`,
*setActivationPolicy(.accessory)*.

**desktop-local** — the overlay's `collectionBehavior` (`.stationary`,
`.ignoresCycle`, `.fullScreenAuxiliary`), which makes it ride the Space slide
with the desktop rather than floating above every Space.
`Sources/Halo/Border.swift`, *BorderController.init*.

---

## 2. The event seam

**seam** — the private-SkyLight subscription that delivers window MOVE / RESIZE /
REORDER / FRONT events at ~5ms (median 4–6ms, no long tail). It is the whole
reason halo tracks a drag smoothly; the public Accessibility path is too slow for
this. All read/observe-only, so SIP can stay on.
`Sources/Halo/WindowServerEvents.swift`, *header*.

**dedicated connection** — a `SLSNewConnection` of halo's own (`cid`), NOT the
process's main SkyLight connection. This is the non-obvious part of the whole
file, verified empirically before the code existed: on the main connection an
AppKit app receives **nothing**, because AppKit owns and services it — notify
procs registered there never fire, even with the drain pump. The dedicated
topology is what yabai, sketchybar and JankyBorders all converge on.
`Sources/Halo/WindowServerEvents.swift`, *WindowServerEvents.start()*.

**notify proc** — the C callback registered per event code with
`SLSRegisterConnectionNotifyProc`. Because a `@convention(c)` function cannot
capture context, it routes through file-scope globals; halo has exactly one
subscriber and one connection, which is what makes that safe.
`Sources/Halo/WindowServerEvents.swift`, *connectionNotify*.

**drain pump** — the `CFMachPort` callback that drains the event port with
`SLEventCreateNextEvent`. Its purpose is easy to misread: **draining is what
dispatches the notify procs**. Without the pump the registrations are live and
silent. `Sources/Halo/WindowServerEvents.swift`, *drainPump*.

**event port** — `SLSGetEventPort(cid)`, wrapped in a `CFMachPort` and added to
the main run loop as a source. The wire between the connection and the pump.
`Sources/Halo/WindowServerEvents.swift`, *wireEventPort(_:)*.

**per-window subscription** — `SLSRequestNotificationsForWindows`, which is what
turns MOVE / RESIZE on for specific window ids. **FULL-REPLACE**: each call
replaces the whole set, so the current set must be re-issued whenever it changes.
Forgetting that is how a newly-opened window silently stops emitting.
`Sources/Halo/WindowServerEvents.swift`, *requestWindows(_:)*.

**event code** — the four raw `UInt32`s halo subscribes to: `806` MOVE, `807`
RESIZE, `808` REORDER (same-app window switch), `1508` FRONT (app switch). MOVE
is deliberately excluded from logging — it fires continuously during a drag.
`Sources/Halo/WindowServerEvents.swift`, *WindowServerEvents.MOVE*.

**safety-net poll** — the 0.4s timer that re-subscribes the on-screen set and
re-hugs regardless of events. Not the tracking mechanism (the seam is); it is the
backstop, so a window opened after launch starts emitting and a missed event
cannot leave the ring stale. It also carries the config mtime check. Owned by
the controller, like the config it re-reads. `Sources/Halo/Border.swift`,
*BorderController.start()*.

**settle re-resolve** — the 16 / 40 / 80ms re-checks fired after FRONT or
REORDER. Both codes arrive BEFORE the window server's z-order settles, so an
immediate resolve reads the OLD front and misses. Whichever re-check first sees
the new front logs and flashes. Without it the poll eventually catches up —
visibly late. (JankyBorders defers ~50ms for the same reason.)
`Sources/Halo/Border.swift`, *BorderController.onEvent(_:)*.

---

## 3. Resolving focus

**resolve** — to pick, from one window-server snapshot, which window the ring
should be on: the frontmost window that is not halo's own, not excluded, and not
tiny. Note what it is NOT — halo never asks the system "what is focused"; it
reads z-order. Pure: it consumes *snapshots* and asks the app only "is this pid
excluded?". `Sources/HaloCore/FocusResolver.swift`,
*FocusResolver.focused(in:selfPID:minSize:isExcluded:)*.

**snapshot** — a `WindowSnapshot`: one on-screen window reduced to its id, its
owning pid and its CG bounds, in the order the window server listed it. The seam
between the window-list read (app) and the resolve (core): the resolve never
sees a `CGWindowList` dictionary. `Sources/HaloCore/FocusResolver.swift`,
*WindowSnapshot*.

**layer-0** — the `kCGWindowLayer == 0` filter: normal application windows. It
excludes the desktop, the menu bar, and floating panels — including halo's own
class of overlay. `Sources/Halo/Border.swift`, *windowInfo()*.

**front-to-back** — the order `CGWindowListCopyWindowInfo` returns with
`.optionOnScreenOnly`, which the resolve consumes by taking the first match. The
ordering IS the focus signal; nothing sorts it afterwards.
`Sources/Halo/Border.swift`, *windowInfo()*.

**exclusion** — an `[exclude].apps` bundle-id glob that suppresses the ring for
matching apps. The glob test is pure (`HaloConfig.isExcluded(bundleID:)`); the
pid → bundle-id lookup is the app's, and lazy — only done when an exclusion is
actually configured, so the common empty case costs nothing.
`Sources/Halo/Border.swift`, *BorderController.isExcluded(pid:)*.

**min-size** — the `minSize` floor (default 80pt) that drops tiny popups from the
resolve, so a completion popup or a tooltip does not steal the ring.
`Sources/HaloCore/HaloConfig.swift`, *minSize*.

**first resolve** — the launch-time resolve, tracked by `didFirstResolve`. The
shake and the sound are gated on it, because at launch the user did not change
focus — halo just started. The flag is set once and never reset, deliberately:
gating on `lastWID` instead would suppress the feedback after any transient
defocus, since the no-focus branch resets that to 0.
`Sources/Halo/Border.swift`, *didFirstResolve*.

---

## 4. Focus feedback

**the three modalities** — halo answers "focus changed" in three independent
ways, and they are separate features with separate costs: the visual **flash**,
the physical **focus-shake**, the audible **focus-sound**. Only the shake needs a
permission. Naming them as one group matters because a change to "focus feedback"
almost always means exactly one of them.

**flash** — a 5-blink burst through the current effect's palette, pre-rolled on a
focus change and decayed by wall clock. A no-op when the effect is off or
palette-less, in which case the ring just re-hugs silently. The burst math is
sill's, not halo's. `Sources/Halo/BorderFX.swift`, *flash()*.

**focus-shake** — a quick horizontal jiggle of the focused window on focus
change. On by default; `shake = false` keeps halo permission-free. See §5 — it is
the only part of halo that is not read-only. `Sources/Halo/WindowShake.swift`.

**focus-sound** — a user-supplied audio cue on focus change, OFF by default. halo
ships no sound of its own (no bundled asset — the same leanness as the ring
carrying no panel theme). Needs no permission: audio playback is unrestricted
with SIP on. `Sources/Halo/FocusSound.swift`.

**latest-wins** — the sound's overlap policy: each `play()` restarts the in-flight
sound, so an alt-tab burst never stacks into noise; only the newest window's cue
is heard. `NSSound` in-process is chosen over spawning `afplay` per focus so a
long-running agent spawns nothing and decodes the file once.
`Sources/Halo/FocusSound.swift`, *play()*.

---

## 5. The shake in detail

**read-only vs moves** — the line that decides halo's permission story. The ring,
the flash and the sound are read-only (private SkyLight reads plus a
click-through overlay) and need NOTHING. The shake writes `kAXPositionAttribute`
on another app's window, so it needs Accessibility. Keep the two halves distinct
when describing halo: "halo needs Accessibility" is false unless the shake is on.
`Sources/Halo/WindowShake.swift`, *header*.

**AX trust** — `AXIsProcessTrusted()`, re-checked on every `fire()` rather than
cached. That is why granting the permission takes effect live, with no restart.
`Sources/Halo/WindowShake.swift`, *trusted*.

**deferred shake** — the mouse-driven case. A focus change while a button is held
is ambiguous: a plain click-to-focus (which SHOULD shake) or the start of a
window drag (which must NOT — halo's position sine would land on top of the OS's
cursor-track and yank the window off the cursor). halo cannot tell them apart
until the gesture ends, so it starts nothing and holds the decision. Keyboard and
programmatic focus changes shake immediately.
`Sources/Halo/WindowShake.swift`, *armDeferred(pid:wid:)*.

**drag threshold** — the 6pt of pointer travel that resolves a deferred shake:
travel past it and the gesture was a drag (drop the shake), release within it and
it was a click (shake now). `Sources/Halo/WindowShake.swift`, *dragThreshold*.

**envelope** — the `(1 − p)` decay term in
`x(p) = origin.x + amplitude · sin(2π·cycles·p) · (1 − p)`. It does two jobs: it
tapers the swing, and it guarantees `x(1) == origin.x`, so the final write lands
on the EXACT origin. That exactness is why the shake never disturbs neighbours,
and why a co-running facet just sees the window return to its base frame.
`Sources/HaloCore/ShakeCurve.swift`, *ShakeCurve.offset(progress:amplitude:)*.

**position-only** — the shake never touches `y` and never touches size. A
left-right nudge, nothing else. `Sources/Halo/WindowShake.swift`, *header*.

**lazy-AX** — an app (Chrome, Calendar) that does not surface a movable focused
window over Accessibility, so `fire()` no-ops on it. A known, accepted
limitation, not a bug to chase. `Sources/Halo/WindowShake.swift`,
*axWindow(in:matching:)*.

---

## 6. One clock

**the one clock** — the single `CACurrentMediaTime()` sample taken per `draw(_:)`
and shared by the border style and the orbiting pets. Both walk on the exact same
`now`, which is what keeps a flash boundary consistent between them. Sampling
twice in one frame is the bug this name exists to prevent.
`Sources/Halo/Border.swift`, *RingView.draw(_:)*.

**redraw heartbeat** — the one 30 Hz timer that pumps `needsDisplay` while
anything animates. It is a CADENCE, not an animator: it decides *when* to
repaint, never *what* colour. It parks itself entirely when the border is static
and no pets are configured, and self-stops from inside its own tick once the
flash burst settles. `Sources/Halo/Border.swift`, *syncRedraw()*.

**clockless math** — sill's `resolveBorder` / `rollFlash`: pure functions of
`now`, holding no timer and no state. The width breathing, the 5-blink burst and
the rainbow / cycle / steady resolve all live there, shared byte-for-byte with
facet. halo keeps only the app-side bits — materializing an `NSColor`, and the
configurable `baseColor` fallback for "off" (halo has no panel palette, so it
cannot fall back to facet's per-surface `pal.primary`).
`Sources/Halo/BorderFX.swift`, *header*.

**sample** — to ask `BorderFX` for the ring's colour and width at a given `now`.
Called exactly once per repaint so colour and width cannot straddle a flash
boundary. `Sources/Halo/BorderFX.swift`, *sample(at:)*.

**animating** — whether the BORDER ITSELF is in motion (rainbow, cycle-colors,
breathing, or a flash burst mid-flight). The heartbeat ORs this with "has
line-pets" to decide whether to keep ticking; the two conditions are separate
because pets orbit forever while the border may be perfectly static.
`Sources/Halo/BorderFX.swift`, *animating(at:)*.

**breathe** — the width oscillation, which turns on only when BOTH `min-width`
and `max-width` are set and `max > min`. Distinguish from **cycle** — the
*colour* loop, driven by `color-cycle-ms`, which `rainbow` does inherently and
other effects do only with `cycle-colors = true`. One config period drives both,
but they are different animations. `Sources/Halo/BorderFX.swift`, *breathing*.

**line-pets** — small arcade sprites (`chomp`, `ghost`) that orbit the ring,
chasing each other. Opt-in, permission-free, theme-agnostic. halo owns only the
rect and the redraw cadence; the drawing is sill's `drawLinePets`. Their speed is
derived from a desired LAP TIME rather than a constant pt/s, so the orbit feels
equally lively on a large and a small window (`Sources/HaloCore/PetOrbit.swift`,
*PetOrbit.speed(around:lapSeconds:)*). `Sources/Halo/Border.swift`,
*RingView.draw(_:)*.

---

## 7. Config

**config-driven** — halo's defining CLI decision: `~/.config/halo/config.toml` is
the *entire* control plane, and there is no runtime control CLI. Under atelier
Phase 3 (unifying the family's CLI grammar) halo is deliberately OUT of the
domain-verb grammar, because inventing a control CLI would be a feature, not a
refactor. `Sources/Halo/HaloApp.swift`, *header*.

**hot-reload** — re-reading and re-applying the config when its mtime changes,
within ~0.4s, no restart. Triggered off the existing safety-net poll rather than
a file watcher, which also covers editors that atomically REPLACE the file (mtime
and inode change either way). One `applyConfig` path serves both launch and
reload, so every tunable lands the same way.
`Sources/Halo/Border.swift`, *reloadIfConfigChanged()*.

**the spec** — `configSpec`, one declarative `ConfigSchema.Spec<HaloConfig>` that
drives BOTH the decode and the emitted JSON Schema. The point is that a key
cannot exist in the parser but be missing from the schema, or vice versa. Its
enum domains come from sill's `canonicalEffectNames` / `canonicalLinePetNames`
rather than being restated. `Sources/HaloCore/HaloConfig+Spec.swift`, *configSpec*.

**schema sidecar** — `config.schema.json`, written next to the user's config on
launch so editor completion and validation just work. Idempotent, writes only on
change, and the hot-reload watcher polls `config.toml` rather than this sibling —
so refreshing it cannot cause reload churn.
`Sources/HaloCore/HaloConfig+Spec.swift`, *installSchema()*.

**clamp-to-default** — the config error policy: an unknown or malformed key keeps
its default rather than failing. A typo can never break the ring. Note this is
the OPPOSITE of the argv policy below, and deliberately so — a config is edited
live by a human, argv is not. `Sources/HaloCore/HaloConfig.swift`, *header*.

**glob** — the anchored, case-insensitive `*` / `?` match used by
`[exclude].apps`. The same grammar wand's exclusion list documents, so one
exclusion list reads the same family-wide. `Sources/HaloCore/HaloConfig.swift`,
*globMatch(_:_:)*.

**no silent fallback** — the argv policy: any argument other than
`--emit-schema` / `--help` / `-h` exits **2**, loudly, on stderr. halo must never
start up silently having ignored what it was told. A normal agent launch (`open
Halo.app`, brew services, a LaunchAgent) passes empty argv, so this never blocks
startup. `Sources/Halo/HaloApp.swift`, *HaloApp.main()*.

---

## 8. Boundaries

**satellite** — halo's relationship to facet, and the reason this repo exists
separately: adjacent features live as sibling repos. facet stays a minimal window
manager; the border effects, the flash, the shake and the sound live here. The
focus-shake in particular is the satellite of facet's reverted feature of the
same name. halo needs nothing from facet and pairs with it by choice. `README.md`.

**what sill owns** — the shared math and drawing: the effect catalog
(`EffectSpec`), the clockless border resolve, the flash roll, `drawLinePets`, the
colour-token grammar, and `ConfigSchema`. The standing direction is to EXTEND the
library rather than reimplement — the north star being "never say *copy facet's
theme* again". `CLAUDE.md`, *Shared libraries*.

**what halo owns** — the window-event seam, the overlay and its geometry, the
resolve, the three feedback modalities, the redraw cadence, and the config
surface. Everything here is app-side by necessity, not by preference.

**Core vs App** — the two modules. `HaloCore` is pure: the config decode and
schema, the resolve over snapshots, the overlay ↔ ring geometry, the shake
curve, the pet orbit speed, and `Log` — nothing that imports AppKit, SkyLight
or AX, so all of it runs under `Tests/HaloCoreTests` with no window server.
`Halo` is the executable: the event seam, the overlay window, `BorderFX`'s
`NSColor` materialization, the AX shake, the sound. The test is the placement
rule: pure math or pure data goes in Core even when its only caller is the app.
`Package.swift`, *header*.

**mirror** — halo's `[border]` config keys deliberately reproduce facet's, key
for key and semantic for semantic, so the two feel the same to a user who runs
both. When adding a border knob, the question is what facet calls it, not what
reads best in isolation. `Sources/HaloCore/HaloConfig.swift`, *header*.
