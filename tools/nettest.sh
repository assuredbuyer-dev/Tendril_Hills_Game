#!/usr/bin/env bash
# =============================================================
# nettest.sh — start a host and a guest, prove they agree.
# -------------------------------------------------------------
#   ./tools/nettest.sh
#
# Two real processes, one real socket. The single-machine
# selftest.sh cannot catch a networking bug, because on one
# machine every request short-circuits to "I have authority, just
# do it". This is the only test that exercises the wire.
#
# Both logs are kept in .nettest/ if you need to read them.
# =============================================================
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_godot() {
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  local candidates=(
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
  )
  local d="$PROJECT_DIR"
  for _ in 1 2 3 4; do
    d="$(dirname "$d")"
    [ "$d" = "/" ] && break
    candidates+=("$d/Godot.app/Contents/MacOS/Godot")
  done
  for app in "${candidates[@]}"; do
    [ -x "$app" ] && { echo "$app"; return; }
  done
  return 1
}
GODOT="${GODOT:-$(find_godot || true)}"
[ -z "$GODOT" ] && { echo "Could not find Godot." >&2; exit 1; }

OUT="$PROJECT_DIR/.nettest"
mkdir -p "$OUT"

# The two processes must not share a save file, or the guest loads
# the host's world off disk and the test proves nothing.
HOST_HOME="$OUT/host_home"; GUEST_HOME="$OUT/guest_home"
mkdir -p "$HOST_HOME" "$GUEST_HOME"

echo "--- starting host ---"
HOME="$HOST_HOME" "$GODOT" --path "$PROJECT_DIR" --headless \
  -- --nettest=host > "$OUT/host.log" 2>&1 &
HOST_PID=$!
sleep 4      # let it bind the port and start its beacon

echo "--- starting guest ---"
HOME="$GUEST_HOME" "$GODOT" --path "$PROJECT_DIR" --headless \
  -- --nettest=guest > "$OUT/guest.log" 2>&1
GUEST_RC=$?

wait $HOST_PID 2>/dev/null
HOST_RC=$?

echo
echo "=============== GUEST ==============="
grep -E "^\s+(ok|FAIL|\.\.)|^\[guest\]|checks,|FAILED:|SCRIPT ERROR" "$OUT/guest.log" || true
echo
echo "=============== HOST ================"
grep -E "^\[host\]|SCRIPT ERROR" "$OUT/host.log" || true
echo

ERRS=$(cat "$OUT/host.log" "$OUT/guest.log" | grep -c "SCRIPT ERROR" || true)
if [ "$ERRS" -gt 0 ]; then
  echo "FAILED: $ERRS script error(s). See $OUT/*.log" >&2
  exit 1
fi
[ "$GUEST_RC" -ne 0 ] && { echo "FAILED: guest reported failures." >&2; exit 1; }
echo "network test passed."
exit 0
