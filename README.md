# halo

A neon ring around your active window on macOS. It hugs the focused
window, **follows it smoothly as you drag** (window-server events at
~5ms — not the laggy AX path), and **pulses — and can shake the focused
window —** on focus change so you always know where you are.

Part of the **facet** family — pairs naturally with the
[facet](https://github.com/akira-toriyama/facet) window manager but
needs nothing from it. (facet stays a minimal window manager; halo is a
separate, focused tool — see facet's "adjacent features live as sibling
repos" decision.)

[日本語 README](README.ja.md)

## Requirements

- Apple Silicon, macOS 13+
- SIP can stay **on**. The ring itself is read-only (private SkyLight +
  a click-through overlay). The optional **focus-shake** moves the
  focused window via Accessibility — grant halo Accessibility for that,
  or set `shake = false` to keep halo permission-free.

## Install

**Homebrew (build from source):**

```sh
brew install akira-toriyama/tap/halo
open "$(brew --prefix)/opt/halo/Halo.app"
```

**Prebuilt (`Halo.zip` from [Releases](https://github.com/akira-toriyama/halo/releases)):**
the app is ad-hoc signed (not notarized), so macOS quarantines it on
download. After unzipping to `/Applications`:

```sh
xattr -dr com.apple.quarantine /Applications/Halo.app
open /Applications/Halo.app
```

halo is an `LSUIElement` agent (no Dock icon, never steals focus). The
ring needs **no permissions**. The **focus-shake** (on by default) moves
the focused window, which needs **Accessibility** — on first launch grant
halo in System Settings → Privacy & Security → Accessibility (or set
`shake = false` to keep halo permission-free).

## Configure

halo reads `~/.config/halo/config.toml` (optional — it has sensible
defaults). Copy the template and edit:

```sh
mkdir -p ~/.config/halo
curl -fsSL https://raw.githubusercontent.com/akira-toriyama/halo/main/config.toml \
  -o ~/.config/halo/config.toml
```

Keys mirror facet's `[border]` surface:

- `effect` — `off | neon | cyber | vapor | kawaii | rainbow | chomp | random`
  (the palette layered on the ring; the focus flash blinks through it.
  `chomp` is the cross-app arcade effect shared with facet & wand —
  blue at rest, blinking pellet-yellow / ghost-red)
- `glow`, `width`, `color` (resting color when `effect = off`)
- `color-cycle-ms`, `cycle-colors` (loop a non-rainbow effect through its
  palette), `min-width` / `max-width` (set both to make the width breathe)
- `corner-radius`, `pad`, `min-size`
- `[exclude]` — `apps` (bundle-id globs that never get a ring, e.g.
  `["com.apple.finder", "*chrome*"]` — the family-shared shape)
- `[shake]` — `shake` (focus-shake on/off), `shake-amplitude` (peak
  horizontal swing in points), `shake-duration-ms`. On focus change the
  focused window does a quick horizontal jiggle and snaps back to its
  exact origin (position only — neighbours untouched). Moves the window
  via Accessibility; lazy-AX apps (Chrome, Calendar) won't move.
- `[sound]` — `sound` (path to an audio file; empty = off),
  `sound-volume` (`0.0`–`1.0`). Plays a short cue on focus change — a
  third focus feedback alongside the ring flash and the shake. Needs no
  permission, ships no bundled sound (point it at your own file), and is
  latest-wins so a fast alt-tab burst never stacks.
- `[pets]` — `line-pets` (a list of arcade sprites that **orbit the ring**
  of the focused window, e.g. `["chomp", "ghost"]`; empty `[]` = off),
  `pet-scale`, `pet-lap-seconds` (time to circle the window once, constant
  at any window size). Small pets chase each other around the ring.
  Opt-in, needs no permission, theme-agnostic (each pet's silhouette is
  its own colour). The shared sill drawing — facet's tree and wand's cards
  grow the same pets.

Unknown or malformed keys are ignored and keep the default. Edits apply
**live** — halo hot-reloads `config.toml` within ~0.4s, no restart.

## Build / run (dev)

The deploy flow mirrors facet's: `package.sh` assembles `Halo.app`,
`run.sh` builds + relaunches it, releases are a rolling GitHub draft, and
Homebrew is bumped automatically on publish.

```sh
./run.sh          # build release → assemble Halo.app → relaunch (HALO_DEBUG on → /tmp/halo.log)
./stop.sh         # kill every running halo (bundle or raw binary)
./package.sh      # just assemble Halo.app (ad-hoc signed)

swift build -c release && .build/release/halo &   # raw binary, no bundle
```

halo touches no TCC-gated APIs, so — unlike facet — there's no
self-signed-cert step and no dev/release bundle split: ad-hoc signing is
enough. Commits follow the facet-family gitmoji + Conventional Commits
convention (`git config core.hooksPath scripts/hooks`; see
[docs/commit-convention.md](docs/commit-convention.md)).

## How it works

A dedicated SkyLight connection subscribes to window MOVE / RESIZE /
front-change events and drains them on the main run loop. That dedicated
connection is the key: an AppKit app can't receive these on the process's
main SkyLight connection (AppKit owns it), which is the trap that makes
the AX-based approaches feel a beat late. See
`Sources/Halo/WindowServerEvents.swift`.
