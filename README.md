# halo

A neon ring around your active window on macOS. It hugs the focused
window, **follows it smoothly as you drag** (window-server events at
~5ms — not the laggy AX path), and **pulses on focus change** so you
always know where you are.

Part of the **facet** family — pairs naturally with the
[facet](https://github.com/akira-toriyama/facet) window manager but
needs nothing from it. (facet stays a minimal window manager; halo is a
separate, focused tool — see facet's "adjacent features live as sibling
repos" decision.)

[日本語 README](README.ja.md)

## Requirements

- Apple Silicon, macOS 13+
- SIP can stay **on**. halo only *observes* the window server (read-only
  private SkyLight) and draws a transparent overlay — it never moves or
  touches your windows.

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

halo is an `LSUIElement` agent (no Dock icon, never steals focus) and
needs **no permissions** — it only reads window geometry via read-only
private SkyLight and draws a click-through overlay. Just launch it.

## Configure

halo reads `~/.config/halo/config.toml` (optional — it has sensible
defaults). Copy the template and edit:

```sh
mkdir -p ~/.config/halo
curl -fsSL https://raw.githubusercontent.com/akira-toriyama/halo/main/config.toml \
  -o ~/.config/halo/config.toml
```

Keys mirror facet's `[border]` surface:

- `effect` — `off | neon | cyber | vapor | kawaii | rainbow | random`
  (the palette layered on the ring; the focus flash blinks through it)
- `glow`, `width`, `color` (resting color when `effect = off`)
- `cycle-seconds`, `cycle-colors` (loop a non-rainbow effect through its
  palette), `min-width` / `max-width` (set both to make the width breathe)
- `corner-radius`, `pad`, `min-size`, `exclude`

Unknown or malformed keys are ignored and keep the default.

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
