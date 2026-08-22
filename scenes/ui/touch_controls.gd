# =============================================================
# touch_controls.gd — a thumbstick and three buttons, for iPad.
# -------------------------------------------------------------
# Shown only where Controls.wants_touch_ui() says so, which is a
# real touch device or `--touch` on the command line. A MacBook
# never sees it.
#
# TWO DIFFERENT MECHANISMS, on purpose:
#
#   The BUTTONS synthesise real input actions through
#   Input.action_press / action_release. So every
#   `Input.is_action_just_pressed("interact")` already in the game
#   works on a tablet with no change at all -- the game cannot
#   tell a thumb from the E key, and there is no second code path
#   to keep in step.
#
#   The STICK cannot do that, because an action is on or off and a
#   thumbstick is the whole reason you can walk slowly. It writes
#   an analog vector to Controls.touch_move, which the player
#   blends with the keyboard.
#
# Everything is drawn, not textured, like the rest of this game.
# =============================================================
class_name TouchControls
extends CanvasLayer

const STICK_RADIUS := 96.0        # how far the knob travels
const STICK_DEADZONE := 0.14
const KNOB_RADIUS := 42.0
const MARGIN := 44.0

var _stick_home: Vector2
var _stick_touch: int = -1        # which finger owns the stick, -1 for none
var _stick_vec: Vector2 = Vector2.ZERO

var _stick_base: Control
var _knob: Control
var _screen: Control


func _ready() -> void:
	# Above the HUD (10) so the buttons are tappable, below the
	# lobby (20) so it cannot be pressed through the join screen.
	layer = 15
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

	_build_stick()
	_build_buttons()
	set_process_input(true)


# --- The stick ------------------------------------------------

func _build_stick() -> void:
	_stick_base = _ring(STICK_RADIUS, Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.30))
	_stick_base.anchor_left = 0.0
	_stick_base.anchor_top = 1.0
	_stick_base.anchor_right = 0.0
	_stick_base.anchor_bottom = 1.0
	_stick_base.offset_left = MARGIN
	_stick_base.offset_top = -MARGIN - STICK_RADIUS * 2.0
	_stick_base.offset_right = MARGIN + STICK_RADIUS * 2.0
	_stick_base.offset_bottom = -MARGIN
	_screen.add_child(_stick_base)

	_knob = _ring(KNOB_RADIUS, Palette.UI_PANEL, Palette.EARTH_DARK)
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_knob)
	_reset_knob()


func _stick_centre() -> Vector2:
	return _stick_base.global_position + _stick_base.size * 0.5


func _reset_knob() -> void:
	_stick_vec = Vector2.ZERO
	Controls.touch_move = Vector2.ZERO
	_place_knob(_stick_centre())


func _place_knob(at: Vector2) -> void:
	_knob.global_position = at - Vector2(KNOB_RADIUS, KNOB_RADIUS)


## Raw touch handling rather than a Button, because a thumbstick
## has to keep tracking the finger after it slides off the ring,
## and it has to ignore the OTHER finger that is pressing E at the
## same time. Godot gives every touch an index; the stick claims
## one and ignores the rest until that one lifts.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _stick_touch == -1 and _in_stick_zone(t.position):
				_stick_touch = t.index
				_drag_to(t.position)
		elif t.index == _stick_touch:
			_stick_touch = -1
			_reset_knob()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_drag_to(d.position)

	# So the thing can be driven with a mouse for testing on desktop.
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _stick_touch == -1 and _in_stick_zone(mb.position):
			_stick_touch = -2
			_drag_to(mb.position)
		elif not mb.pressed and _stick_touch == -2:
			_stick_touch = -1
			_reset_knob()
	elif event is InputEventMouseMotion and _stick_touch == -2:
		_drag_to((event as InputEventMouseMotion).position)


## Generous: the whole lower-left quarter starts the stick, not
## just the ring itself. Missing a thumbstick by ten pixels and
## walking nowhere is the single most common tablet-controls
## complaint, and the fix is to stop making people aim.
func _in_stick_zone(pos: Vector2) -> bool:
	var vp := _screen.size
	return pos.x < vp.x * 0.45 and pos.y > vp.y * 0.42


func _drag_to(pos: Vector2) -> void:
	var centre := _stick_centre()
	var off := pos - centre
	if off.length() > STICK_RADIUS:
		off = off.normalized() * STICK_RADIUS
	_place_knob(centre + off)
	var v := off / STICK_RADIUS
	if v.length() < STICK_DEADZONE:
		v = Vector2.ZERO
	_stick_vec = v
	Controls.touch_move = v


# --- The buttons ----------------------------------------------

func _build_buttons() -> void:
	# Bottom right, thumb-sized, in the order they get used.
	_action_button("E", 104, Palette.MOSS, "interact", Vector2(-MARGIN, -MARGIN))
	_action_button("Jump", 84, Palette.SKY_BLUE, "jump",
		Vector2(-MARGIN - 118.0, -MARGIN - 26.0))
	# Camera swing, small, above the others.
	_action_button("<", 62, Palette.UI_PANEL_DIM, "cam_left",
		Vector2(-MARGIN - 152.0, -MARGIN - 132.0))
	_action_button(">", 62, Palette.UI_PANEL_DIM, "cam_right",
		Vector2(-MARGIN - 80.0, -MARGIN - 132.0))
	# There is no H key on a tablet, so without this the controls card
	# can be dismissed and never brought back. It also carries the
	# live fps readout, which is the only way to judge an old iPad.
	_action_button("?", 52, Palette.UI_PANEL_DIM, "toggle_help",
		Vector2(-MARGIN - 448.0, -MARGIN))

	# The keyboard's 1/2/3. In a row along the bottom rather than a
	# column up the right edge, which ran straight through the help
	# card and the quest list.
	_action_button("Eat", 58, Palette.CARROT, "eat",
		Vector2(-MARGIN - 250.0, -MARGIN))
	_action_button("Seed", 58, Palette.WARM_YELLOW, "cycle_seed",
		Vector2(-MARGIN - 316.0, -MARGIN))
	_action_button("Build", 58, Palette.SOFT_PURPLE, "build_house",
		Vector2(-MARGIN - 382.0, -MARGIN))


## A round clay button that presses a real input action.
func _action_button(text: String, size: float, tint: Color, action: String,
		offset: Vector2) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(size, size)
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset.x - size
	b.offset_top = offset.y - size
	b.offset_right = offset.x
	b.offset_bottom = offset.y
	b.add_theme_font_size_override("font_size", int(size * 0.26))
	b.add_theme_color_override("font_color", Palette.UI_TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.CREAM)
	b.add_theme_stylebox_override("normal", _round_box(tint, 0.55, size))
	b.add_theme_stylebox_override("hover", _round_box(tint, 0.72, size))
	b.add_theme_stylebox_override("pressed", _round_box(tint, 1.0, size))
	b.add_theme_stylebox_override("focus", _round_box(tint, 0.55, size))

	# Held, not tapped: cam_left and cam_right are read with
	# is_action_pressed every frame, so the action has to stay down
	# for as long as the thumb does.
	b.button_down.connect(func(): Input.action_press(action))
	b.button_up.connect(func(): Input.action_release(action))
	_screen.add_child(b)


func _round_box(tint: Color, alpha: float, size: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, alpha)
	sb.set_corner_radius_all(int(size * 0.5))
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(3)
	return sb


func _ring(radius: float, fill: Color, edge: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	c.size = Vector2(radius * 2.0, radius * 2.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.border_color = edge
	sb.set_border_width_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(p)
	return c
