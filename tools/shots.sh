#!/usr/bin/env bash
# =============================================================
# shots.sh — one command, eight screenshots, no hands.
# -------------------------------------------------------------
#   ./tools/shots.sh
#
# Boots Tendril Hills, seeds a mid-season farm, walks the camera
# through eight framings, saves PNGs to .shots/ and quits.
#
# The two things that go wrong if you type this by hand:
#   1. `godot` is not on PATH on macOS — it lives inside the .app.
#      This script finds it.
#   2. Godot swallows unknown flags. Our args must come after a
#      bare `--`, or --shots never reaches the game.
# =============================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/.shots"

# --- Find the Godot binary -----------------------------------
find_godot() {
  if command -v godot >/dev/null 2>&1; then command -v godot; return; fi
  for app in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
    "/Applications/Godot_mono.app/Contents/MacOS/Godot"; do
    [ -x "$app" ] && { echo "$app"; return; }
  done
  return 1
}

GODOT="${GODOT:-$(find_godot || true)}"
if [ -z "$GODOT" ]; then
  cat >&2 <<'EOF'
Could not find Godot.

Fix one of these ways:
  1. Drag Godot.app into /Applications, then rerun this script.
  2. Point at it directly:
       GODOT=/path/to/Godot.app/Contents/MacOS/Godot ./tools/shots.sh
  3. Put it on PATH permanently, in ~/.zshrc:
       alias godot="/Applications/Godot.app/Contents/MacOS/Godot"
EOF
  exit 1
fi

# --- Run ------------------------------------------------------
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "godot:   $GODOT"
echo "project: $PROJECT_DIR"
echo "out:     $OUT_DIR"
echo

"$GODOT" --path "$PROJECT_DIR" \
         --rendering-driver opengl3 \
         --quit-after 900 \
         -- --shots --out="res://.shots"

echo
COUNT=$(find "$OUT_DIR" -name '*.png' | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
  echo "No screenshots were written. Usually this means the game hit a" >&2
  echo "script error on boot — scroll up for the stack trace." >&2
  exit 1
fi
echo "$COUNT screenshots in $OUT_DIR"
ls -1 "$OUT_DIR"
