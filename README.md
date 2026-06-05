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

## Build / run

```sh
swift build -c release
.build/release/halo &           # runs as a background agent (no Dock icon)
HALO_DEBUG=1 .build/release/halo 2>&1 | tee /tmp/halo-run.log   # verbose
```

## Configure

halo reads `~/.config/halo/config.toml` (optional — it has sensible
defaults). Copy the template and edit:

```sh
mkdir -p ~/.config/halo
curl -fsSL https://raw.githubusercontent.com/akira-toriyama/halo/main/config.toml \
  -o ~/.config/halo/config.toml
```

Keys: `color`, `width`, `corner_radius`, `pad`, `glow`, `flash_color`,
`flash_width`, `flash_ms` (0 disables the pulse), `min_size`, `exclude`.
Unknown or malformed keys are ignored and keep the default.

## How it works

A dedicated SkyLight connection subscribes to window MOVE / RESIZE /
front-change events and drains them on the main run loop. That dedicated
connection is the key: an AppKit app can't receive these on the process's
main SkyLight connection (AppKit owns it), which is the trap that makes
the AX-based approaches feel a beat late. See
`Sources/Halo/WindowServerEvents.swift`.
