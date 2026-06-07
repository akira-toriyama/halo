#!/bin/zsh
# Build (release) + relaunch halo locally with HALO_DEBUG on (verbose
# /tmp/halo.log). halo is a plain agent binary — no .app bundle / TCC
# grant needed (read-only SkyLight + a click-through overlay).
#
#   ./run.sh
#
# Quit later: ./stop.sh
set -e
cd "$(dirname "$0")"

swift build -c release
./stop.sh
sleep 0.3
HALO_DEBUG=1 .build/release/halo &
echo "halo launched (HALO_DEBUG on → /tmp/halo.log). Stop: ./stop.sh"
