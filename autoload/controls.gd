# =============================================================
# controls.gd — AUTOLOAD "Controls"
# -------------------------------------------------------------
# Registers the input actions in code rather than in the editor's
# Input Map. Two reasons:
#   1. You can read every binding in one place, in plain text.
#   2. project.godot stays free of the fragile serialised
#      InputEvent blobs that break in merge conflicts.
#
# Runs before everything else (first autoload), so any script can
# assume these actions exist.
# =============================================================
extends Node

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back":    [KEY_S, KEY_DOWN],
	"move_left":    [KEY_A, KEY_LEFT],
	"move_right":   [KEY_D, KEY_RIGHT],
	# Space used to be a second "interact" key. It is the jump key now —
	# every kid who has played anything expects that — so interact is E
	# and Enter only.
	"interact":     [KEY_E, KEY_ENTER],
	"jump":         [KEY_SPACE],
	"eat":          [KEY_1],
	"cycle_seed":   [KEY_2],
	"build_house":  [KEY_3],
	"cam_left":     [KEY_Q],
	"cam_right":    [KEY_R],
	"toggle_help":  [KEY_H],
	"reset_save":   [KEY_F9],
}


func _ready() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)


# =============================================================
#  Touch
# -------------------------------------------------------------
# The on-screen stick writes its position here and the player
# reads it, blended with the keyboard. Buttons do NOT go through
# this: they synthesise real input actions instead (see
# touch_controls.gd), so every existing `Input.is_action_pressed`
# in the game keeps working untouched on a tablet.
#
# Only the stick needs a back channel, because it is analog and an
# action is on or off. Half-speed walking is the whole point of a
# thumbstick and it cannot be faked with a key.
# =============================================================

## -1..1 on each axis, same convention as Input.get_vector.
var touch_move: Vector2 = Vector2.ZERO
## -1..1, how hard the camera is being swung.
var touch_cam: float = 0.0


## Should the game draw an on-screen stick and buttons?
##
## Not "is this iOS" — a Mac with a touch-bar or a plugged-in
## tablet reports a touchscreen too, and a kid on a MacBook does
## not want a thumbstick over their game. Touch UI appears when
## the device is genuinely touch-first, or when asked for.
static func wants_touch_ui() -> bool:
	if "--touch" in OS.get_cmdline_user_args():
		return true
	if "--no-touch" in OS.get_cmdline_user_args():
		return false
	return OS.has_feature("mobile")
