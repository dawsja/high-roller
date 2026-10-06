#!/usr/bin/env bash
# Co-op over real sockets on localhost: one headless host and 1-3 headless
# clients (ENet), each running the scripted NetBot (tools/net_bot.gd) with
# --net-log, on a throwaway copy of the project. Asserts from their logs:
#   - every client connected and the host saw every player join;
#   - every peer spawned every player;
#   - a client's bet resolved on the host and its bet + win-Heat events
#     reached every peer;
#   - a client walked into the cashier zone and the host saw it (and its
#     cash-out request ran on the host);
#   - the clients' puppet guards track the host's guards (within GUARD_TOL m);
#   - the runner client was grabbed, its own body followed its guard's carry
#     point, and the host saw it follow (within CARRY_TOL m);
#   - the crew climbed together: the next visit reached every peer;
#   - no SCRIPT ERROR / Parse Error / ERROR: line anywhere.
#
#   ./tools/net_test.sh [clients=1] [--speed=N] [--timeout=SECONDS] [--keep-logs=DIR]
#
# Exit 0 = pass, 1 = fail, 77 = skipped (could not open a UDP socket on
# localhost). Each run picks a random port (retrying on a collision) and kills
# every process it started on exit.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
CLIENTS=1
SPEED=2
TIMEOUT=240
KEEP=""
GUARD_TOL=2.0
CARRY_TOL=1.5
SELF_TOL=1.0
for arg in "$@"; do
	case "$arg" in
		--speed=*) SPEED="${arg#--speed=}" ;;
		--timeout=*) TIMEOUT="${arg#--timeout=}" ;;
		--keep-logs=*) KEEP="${arg#--keep-logs=}" ;;
		[0-9]*) CLIENTS="$arg" ;;
		*) echo "net_test.sh: unknown argument $arg" >&2; exit 2 ;;
	esac
done
if [ "$CLIENTS" -lt 1 ] || [ "$CLIENTS" -gt 3 ]; then
	echo "net_test.sh: 1 to 3 clients" >&2
	exit 2
fi

WORK="$(mktemp -d)"
PIDS=()
cleanup() {
	for p in "${PIDS[@]:-}"; do
		[ -n "$p" ] && kill "$p" 2>/dev/null
	done
	sleep 0.3
	for p in "${PIDS[@]:-}"; do
		[ -n "$p" ] && kill -9 "$p" 2>/dev/null
	done
	if [ -n "$KEEP" ] && [ -d "$WORK/logs" ]; then
		mkdir -p "$KEEP" && cp "$WORK"/logs/*.log "$KEEP"/ 2>/dev/null
	fi
	rm -rf "$WORK"
}
trap cleanup EXIT
tar -C "$ROOT" --exclude=.git --exclude=.godot -cf - . | tar -C "$WORK" -xf -
"$GODOT" --headless --path "$WORK" --import >"$WORK/.import.log" 2>&1 || true
mkdir -p "$WORK/logs"
LOGS="$WORK/logs"
QUIT=$((TIMEOUT - 10))
SEED=$(( (RANDOM % 900) + 100 ))
COMMON=(--headless --path "$WORK" --audio-driver Dummy)
GAME=(--net-bot --net-log --speed="$SPEED" --quit-after-seconds="$QUIT")

# --- Host (retry on a port collision) -------------------------------------------
PORT=0
HOST_PID=""
for attempt in 1 2 3 4; do
	PORT=$(( 20000 + (RANDOM % 30000) ))
	"$GODOT" "${COMMON[@]}" -- --host="$PORT" --name=Host --autostart --players=$((CLIENTS + 1)) \
		--practice --rung=6 --seed="$SEED" "${GAME[@]}" >"$LOGS/host.log" 2>&1 &
	HOST_PID=$!
	PIDS+=("$HOST_PID")
	for i in $(seq 1 150); do
		if grep -qE "NET .* (hosted|failed)" "$LOGS/host.log" 2>/dev/null; then break; fi
		if ! kill -0 "$HOST_PID" 2>/dev/null; then break; fi
		sleep 0.1
	done
	if grep -q "NET .* hosted" "$LOGS/host.log"; then
		break
	fi
	kill "$HOST_PID" 2>/dev/null
	HOST_PID=""
done
if [ -z "$HOST_PID" ]; then
	echo "net_test.sh: SKIP: could not host on a localhost UDP port (sockets unavailable?)"
	grep -E "NET .* failed|ERROR" "$LOGS/host.log" | head -5
	exit 77
fi
echo "net_test.sh: host on 127.0.0.1:$PORT, $CLIENTS client(s), speed $SPEED, seed $SEED"

# --- Clients ----------------------------------------------------------------------
CLIENT_PIDS=()
for c in $(seq 1 "$CLIENTS"); do
	"$GODOT" "${COMMON[@]}" -- --join=127.0.0.1:"$PORT" --name="Bot$c" "${GAME[@]}" >"$LOGS/client$c.log" 2>&1 &
	CLIENT_PIDS+=($!)
	PIDS+=($!)
	sleep 0.3
done

# --- Wait -------------------------------------------------------------------------
START=$(date +%s)
while :; do
	ALIVE=0
	for p in "${PIDS[@]}"; do
		kill -0 "$p" 2>/dev/null && ALIVE=$((ALIVE + 1))
	done
	[ "$ALIVE" -eq 0 ] && break
	if [ $(( $(date +%s) - START )) -gt "$TIMEOUT" ]; then
		echo "net_test.sh: timeout after ${TIMEOUT}s, killing the peers"
		break
	fi
	sleep 0.5
done
ELAPSED=$(( $(date +%s) - START ))

# --- Checks -----------------------------------------------------------------------
FAILS=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# Field value of a NET line: field <name> < lines
field() { sed -n "s/.* $1=\([^ ]*\).*/\1/p"; }
# Largest err= of matching lines (empty if none).
max_err() { grep -E "$2" "$1" | field err | sort -g | tail -1; }
count() { grep -cE "$2" "$1" 2>/dev/null || true; }
le() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a != "" && a + 0 <= b + 0) }'; }

ALL_LOGS=("$LOGS/host.log")
for c in $(seq 1 "$CLIENTS"); do ALL_LOGS+=("$LOGS/client$c.log"); done
CREW="$(grep -E "NET .* run_start" "$LOGS/host.log" | head -1 | field crew)"
PIDS_LINE="$(grep -E "NET .* player_joined" "$LOGS/host.log" | tail -1 | field pids)"
IFS=',' read -r -a CREW_PIDS <<< "${PIDS_LINE:-1}"
RUNNER_PID="$(grep -E "NET pid=1 .* bot=make_wanted" "$LOGS/host.log" | head -1 | field runner)"
CLIENT1_PID="$(grep -E "NET .* connected pids=" "$LOGS/client1.log" | head -1 | sed -n 's/NET pid=\([0-9]*\) .*/\1/p')"
echo "net_test.sh: crew ${PIDS_LINE:-?} (run_start crew=${CREW:-?}), first client $CLIENT1_PID, runner ${RUNNER_PID:-none}, ${ELAPSED}s"

check "the run started with the whole crew ($((CLIENTS + 1)))" '[ "${CREW:-0}" = "$((CLIENTS + 1))" ]'
for c in $(seq 1 "$CLIENTS"); do
	check "client $c connected" 'grep -qE "NET pid=[0-9]+ .* connected pids=" "$LOGS/client$c.log"'
done
for log in "${ALL_LOGS[@]}"; do
	name="$(basename "$log" .log)"
	missing=""
	for p in "${CREW_PIDS[@]}"; do
		grep -qE "NET .* spawned pid=$p " "$log" || missing="$missing $p"
	done
	check "$name spawned every player (${PIDS_LINE:-?})" '[ -z "$missing" ] && [ ${#CREW_PIDS[@]} -eq $((CLIENTS + 1)) ]'
done
C1="${CLIENT1_PID:-x}"
check "host ran client $C1's place_bet" 'grep -qE "NET pid=1 .* request from=$C1 name=place_bet ok=true" "$LOGS/host.log"'
for log in "${ALL_LOGS[@]}"; do
	name="$(basename "$log" .log)"
	check "$name got client $C1's bet event" 'grep -qE "NET .* event kind=bet pid=$C1 " "$log"'
	check "$name got client $C1's win Heat event" 'grep -qE "NET .* event kind=heat pid=$C1 .*reason=(win|shared_roll)" "$log"'
done
if [ "$CLIENTS" -ge 2 ]; then
	SHARED=$(grep -cE "NET pid=1 .* request from=[0-9]+ name=place_bet ok=true .*shared=true" "$LOGS/host.log" || true)
	check "the clients' dice bets went into a shared crew roll ($SHARED)" '[ "$SHARED" -ge 2 ] && grep -qE "NET pid=1 .* event kind=shared_roll .*open=false" "$LOGS/host.log"'
fi
check "host saw client $C1 enter the cashier zone (request)" 'grep -qE "NET pid=1 .* request from=$C1 name=enter_zone ok=true" "$LOGS/host.log"'
check "host saw client $C1 enter the cashier zone (event)" 'grep -qE "NET pid=1 .* event kind=zone pid=$C1 zone=6 " "$LOGS/host.log"'
check "client $C1's cash_out ran on the host" 'grep -qE "NET pid=1 .* request from=$C1 name=cash_out ok=true" "$LOGS/host.log"'
for c in $(seq 1 "$CLIENTS"); do
	n=$(count "$LOGS/client$c.log" "guard_track")
	m=$(max_err "$LOGS/client$c.log" "guard_track")
	check "client $c puppet guard tracks the host's ($n probes, max ${m:-?} m <= $GUARD_TOL)" '[ "${n:-0}" -ge 10 ] && le "$m" "$GUARD_TOL"'
	s=$(max_err "$LOGS/client$c.log" "self_track")
	check "host's copy of client $c follows it (max ${s:-?} m <= $SELF_TOL)" 'le "$s" "$SELF_TOL"'
done
R="${RUNNER_PID:-x}"
RLOG=""
for c in $(seq 1 "$CLIENTS"); do
	grep -qE "NET pid=$R " "$LOGS/client$c.log" && RLOG="$LOGS/client$c.log"
done
check "runner $R was grabbed (caught on the host)" 'grep -qE "NET pid=1 .* event kind=caught pid=$R " "$LOGS/host.log"'
if [ -n "$RLOG" ]; then
	cf=$(count "$RLOG" "carried_follow")
	cm=$(max_err "$RLOG" "carried_follow")
	check "runner's body follows its guard's carry point ($cf samples, max ${cm:-?} m <= 0.25)" '[ "${cf:-0}" -ge 2 ] && le "$cm" 0.25'
	check "runner got the host's carry placement" 'grep -qE "NET pid=$R .* placed pid=$R mode=carry" "$RLOG"'
else
	fail "runner's log not found"
fi
ct=$(count "$LOGS/host.log" "carry_track pid=$R ")
cx=$(max_err "$LOGS/host.log" "carry_track pid=$R ")
check "host sees the carried runner on its guard ($ct samples, max ${cx:-?} m <= $CARRY_TOL)" '[ "${ct:-0}" -ge 2 ] && le "$cx" "$CARRY_TOL"'
check "the crew climbed (host)" 'grep -qE "NET pid=1 .* event kind=climbed " "$LOGS/host.log"'
for log in "${ALL_LOGS[@]}"; do
	name="$(basename "$log" .log)"
	check "$name reached the next visit" 'grep -qE "NET .* visit token=2 rung=5 " "$log"'
done
for log in "${ALL_LOGS[@]}"; do
	name="$(basename "$log" .log)"
	errs=$(grep -cE "SCRIPT ERROR|Parse Error|Failed to load script|ERROR: " "$log" || true)
	check "$name has no errors ($errs)" '[ "$errs" -eq 0 ]'
done

if [ "$FAILS" -gt 0 ]; then
	echo "net_test.sh: $FAILS check(s) failed"
	for log in "${ALL_LOGS[@]}"; do
		echo "--- $(basename "$log") (errors and bot lines)"
		grep -E "SCRIPT ERROR|ERROR: |bot=|failed|visit " "$log" | head -60
	done
	exit 1
fi
echo "net_test.sh: all checks passed (${ELAPSED}s)"
exit 0
