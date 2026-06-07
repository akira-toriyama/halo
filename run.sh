#!/bin/zsh
# Build (release) + assemble Halo.app + relaunch it locally with
# HALO_DEBUG on (verbose /tmp/halo.log).
#
#   ./run.sh
#
# Always kills any currently-running halo first (via stop.sh) so the
# new bundle takes over cleanly. Quit later: ./stop.sh
#
# The ring is read-only, but focus-shake (`shake = true`) moves the
# focused window via AX → grant halo Accessibility once on first run
# (or set shake = false to stay permission-free). For a smooth dev
# loop run ./setup-signing-cert.sh first so the grant survives rebuilds.
set -e
cd "$(dirname "$0")"

./package.sh
./stop.sh
sleep 0.3

# `open` doesn't inherit the calling shell's environment (macOS Launch
# Services starts the .app in its own context), so HALO_DEBUG is passed
# through explicitly via --env. There is no `--debug` flag — debug is
# env-var-triggered, so a brew / raw `open Halo.app` stays quiet.
open ./Halo.app --env HALO_DEBUG=1
echo "Halo.app launched (HALO_DEBUG on → /tmp/halo.log). Stop: ./stop.sh"
