#!/bin/zsh
# Kill every running halo instance (release / debug / raw binary).
# Safe to run when nothing is up (no-op).
#
#   ./stop.sh
set -e
cd "$(dirname "$0")"

pkill -f '\.build/.*/halo' 2>/dev/null || true

remaining="$(ps aux | grep -E '\.build/.*/halo' | grep -v grep || true)"
if [[ -n "$remaining" ]]; then
    echo "warning: some halo instances survived:" >&2
    echo "$remaining" >&2
    exit 1
fi
echo "killed: all halo instances"
