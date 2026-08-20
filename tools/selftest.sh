#!/usr/bin/env bash
# =============================================================
# selftest.sh — press every button in the game, check the result.
# -------------------------------------------------------------
#   ./tools/selftest.sh
#
# Runs headless in a few seconds. Exits non-zero if anything
# failed, so you can run it before you trust a change.
# The screenshot loop can see how the game looks; this sees
# whether it still works.
# =============================================================
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_godot() {
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  for app in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
    [ -x "$app" ] && { echo "$app"; return; }
  done
  return 1
}
GODOT="${GODOT:-$(find_godot || true)}"
[ -z "$GODOT" ] && { echo "Could not find Godot. See tools/shots.sh for how to point at it." >&2; exit 1; }

LOG="$(mktemp)"
"$GODOT" --path "$PROJECT_DIR" --headless -- --selftest 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}

# A GDScript runtime error prints and then execution CARRIES ON, so
# assertions can all pass while the game is throwing on every action.
# That is exactly how a Godot 3 audio call survived into a shipped
# build. Any SCRIPT ERROR fails the run, full stop.
ERRS=$(grep -c "SCRIPT ERROR" "$LOG" || true)
rm -f "$LOG"
if [ "$ERRS" -gt 0 ]; then
  echo
  echo "FAILED: $ERRS script error(s) above. Assertions passing is not enough." >&2
  exit 1
fi
exit "$RC"
