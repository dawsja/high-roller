#!/usr/bin/env bash
# Runs the headless test suite in a throwaway copy of the project, so parallel
# runs never share a .godot cache. Fails on any failed assert, parse error or
# runtime script error. Optional args filter test files by substring.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar -C "$ROOT" --exclude=.git --exclude=.godot -cf - . | tar -C "$WORK" -xf -
"$GODOT" --headless --path "$WORK" --import >"$WORK/.import.log" 2>&1 || true
LOG="$WORK/.test.log"
"$GODOT" --headless --path "$WORK" -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script|ERROR: " "$LOG"; then
	echo "test.sh: engine/script errors found in output (see above)" >&2
	STATUS=1
fi
exit "$STATUS"
