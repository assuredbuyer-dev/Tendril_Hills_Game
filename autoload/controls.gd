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
