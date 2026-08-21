#!/usr/bin/env bash
# =============================================================
# bench.sh — how heavy is the world? Node counts + frame time.
# -------------------------------------------------------------
#   ./tools/bench.sh
#
# Prints how many nodes, meshes and colliders the world builds,
# and the average frame time over four seconds. Run it before
# and after any change that adds a lot of scenery — the world
# getting bigger is easy to ship and hard to un-ship.
#
# Numbers here are your machine's, not a player's. Compare a
# before against an after on the SAME machine; the absolute
# figure means very little on its own.
# =============================================================
set -uo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
find_godot() {
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi

  local candidates=(
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
    "/Applications/Godot_mono.app/Contents/MacOS/Godot"
  )
  # Also walk up from the project. Plenty of people keep Godot.app next
  # to their game folders instead of in /Applications, and a script that
  # only checks /Applications tells them Godot is missing when it is
  # sitting two directories up.
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
[ -z "$GODOT" ] && { echo "Could not find Godot. See tools/shots.sh." >&2; exit 1; }

"$GODOT" --path "$PROJECT_DIR" --rendering-driver opengl3 --resolution 640x360 -- --bench 2>&1 \
  | grep -E "^\[bench\]|SCRIPT ERROR|ERROR" 
