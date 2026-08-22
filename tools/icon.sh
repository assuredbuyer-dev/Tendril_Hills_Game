#!/usr/bin/env bash
# =============================================================
# icon.sh — render the 1024x1024 app icon from the game's own art.
# -------------------------------------------------------------
#   ./tools/icon.sh
#
# Writes icon_1024.png in the project root. Point Godot's iOS
# export at it (Icons -> App Store 1024x1024) and it generates
# every other size from that one file.
#
# Re-run it after changing data/palette.gd and the icon follows
# the game, which is the whole reason it is generated rather than
# drawn. See scenes/dev/icon_maker.gd.
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
    d="$(dirname "$d")"; [ "$d" = "/" ] && break
    candidates+=("$d/Godot.app/Contents/MacOS/Godot")
  done
  for app in "${candidates[@]}"; do [ -x "$app" ] && { echo "$app"; return; }; done
  return 1
}
GODOT="${GODOT:-$(find_godot || true)}"
[ -z "$GODOT" ] && { echo "Could not find Godot." >&2; exit 1; }

"$GODOT" --path "$PROJECT_DIR" --rendering-driver opengl3 \
         --resolution 1024x1024 -- --icon 2>&1 | grep -E "^\[icon\]|SCRIPT ERROR"

[ -f "$PROJECT_DIR/icon_1024.png" ] || { echo "No icon was written." >&2; exit 1; }
