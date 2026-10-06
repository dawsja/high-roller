#!/usr/bin/env bash
# Renders review screenshots of a casino visit under a virtual display
# (xvfb-run) with the OpenGL renderer: the title, the player's third-person
# view, an overhead of the floor, a table mid-result with the bet panel open,
# and a HUD close-up.
#   ./tools/screenshot.sh <out_dir> [rung] [extra args, e.g. --practice --seed=3]
# Works on a throwaway copy of the project (like tools/test.sh).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
OUT="${1:?usage: screenshot.sh <out_dir> [rung] [extra args]}"
RUNG="${2:-6}"
shift $(( $# >= 2 ? 2 : 1 ))
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -C "$ROOT" --exclude=.git --exclude=.godot -cf - . | tar -C "$WORK" -xf -
"$GODOT" --headless --path "$WORK" --import >"$WORK/.import.log" 2>&1 || true
xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path "$WORK" --rendering-driver opengl3 --audio-driver Dummy \
	-s res://tools/screenshot.gd -- --rung="$RUNG" --out="$OUT" "$@" 2>&1 | grep -v "^$"
ls -1 "$OUT"/*.png
