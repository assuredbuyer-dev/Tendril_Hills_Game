# =============================================================
# lobby.gd — the screen before the game.
# -------------------------------------------------------------
# Three buttons and a name box. That is the entire multiplayer
# interface, and it is deliberate: a seven-year-old cannot be
# asked for an IP address, so they are never shown one.
#
# The middle list fills itself in. Any copy of Tendril Hills
# hosting on this wifi shouts its name once a second (see
# Net's beacon), and every name that arrives becomes a button.
# You click your brother's name. That is it.
#
# Built in code like the rest of the UI, so it lives in git as
# text and there is no scene file to merge-conflict over.
# =============================================================
class_name Lobby
extends CanvasLayer

signal ready_to_play()

const NAME_KEY := "user://player_name.txt"

var _name_edit: LineEdit
var _host_list: VBoxContainer
var _status: Label
var _root: VBoxContainer


func _ready() -> void:
	# A CanvasLayer, not a bare Control, and above the HUD's layer 10.
	# A Control parented to the 3D scene draws on the default canvas,
	# which the HUD then covers completely -- the first version of
	# this screen was rendering perfectly, underneath the belly bar.
	layer = 20

	var screen := Control.new()
	screen.name = "Screen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen)

	var bg := ColorRect.new()
	bg.color = Palette.FOG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)

	# Centring a container that sizes itself to its own contents:
	# collapse the rect to nothing at the middle and let grow_* push
	# it outward both ways. PRESET_CENTER subtracts half a size that
	# does not exist yet, which is why the panel was hanging off the
	# top-left corner. Same lesson as hud.gd's _dock.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override("panel", _panel_style())
	screen.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(pad)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 12)
	_root.custom_minimum_size = Vector2(460, 0)
	pad.add_child(_root)

	_add_title("Tendril Hills")
	_add_note("Who is playing?")

	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.text = _load_name()
	_name_edit.placeholder_text = "your name"
	_name_edit.add_theme_font_size_override("font_size", 20)
	_style_field(_name_edit)
	_root.add_child(_name_edit)

	_root.add_child(HSeparator.new())
	_add_note("Play on your own")
	_add_button("Just me", func(): _start_solo())

	_root.add_child(HSeparator.new())
	_add_note("Open your world so others can join")
	_add_button("Host Tendril Hills", func(): _start_host())

	_root.add_child(HSeparator.new())
	_add_note("Join someone on this wifi")
	_host_list = VBoxContainer.new()
	_host_list.add_theme_constant_override("separation", 6)
	_root.add_child(_host_list)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Palette.UI_TEXT_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_status)

	Net.hosts_found.connect(_refresh_hosts)
	Net.connection_failed.connect(_on_failed)
	Net.mode_changed.connect(_on_mode_changed)
	Net.start_scanning()
	_refresh_hosts()


# --- The three ways in ----------------------------------------

func _start_solo() -> void:
	_save_name()
	Net.player_name = _clean_name()
	Net.leave()
	_finish()


func _start_host() -> void:
	_save_name()
	if Net.host_game(_clean_name()):
		_status.text = "Your world is open. The others should see your name now."
		_finish()


func _join(ip: String) -> void:
	_save_name()
	_status.text = "Knocking..."
	Net.join_game(ip, _clean_name())


func _on_mode_changed() -> void:
	# A client only really arrives once the host answers, which is a
	# moment after join_game returns. That is what this waits for.
	if Net.is_client() and is_inside_tree() and visible:
		_finish()


func _finish() -> void:
	Net.stop_scanning()
	hide()
	ready_to_play.emit()


func _on_failed(reason: String) -> void:
	_status.text = reason
	if not visible:
		# Thrown out mid-game -- come back to the lobby rather than
		# leaving a kid staring at a world that is no longer shared.
		show()
		Net.start_scanning()


# --- The list of games on this wifi ---------------------------

func _refresh_hosts() -> void:
	for c in _host_list.get_children():
		c.queue_free()
	if Net.found_hosts.is_empty():
		var waiting := Label.new()
		waiting.text = "Looking... (nobody is hosting yet)"
		waiting.add_theme_color_override("font_color", Palette.UI_TEXT_SOFT)
		_host_list.add_child(waiting)
		return
	for ip in Net.found_hosts:
		var h: Dictionary = Net.found_hosts[ip]
		var b := Button.new()
		b.text = "Join %s   (%d playing)" % [String(h["name"]), int(h["players"])]
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 18)
		_style_button(b)
		var target := String(h["ip"])
		b.pressed.connect(func(): _join(target))
		_host_list.add_child(b)


# --- Odds and ends --------------------------------------------

func _clean_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Sprite"


## The name is remembered because ownership of a homestead is stored
## by name. Retyping it slightly differently tomorrow would look like
## a different player and lose your clearing.
func _save_name() -> void:
	var f := FileAccess.open(NAME_KEY, FileAccess.WRITE)
	if f:
		f.store_string(_clean_name())
		f.close()


func _load_name() -> String:
	if not FileAccess.file_exists(NAME_KEY):
		return ""
	var f := FileAccess.open(NAME_KEY, FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_as_text().strip_edges()
	f.close()
	return n


func _add_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Palette.UI_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(l)


func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Palette.UI_TEXT_SOFT)
	_root.add_child(l)


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	_style_button(b)
	b.pressed.connect(cb)
	_root.add_child(b)


## Godot's stock widgets are flat grey, which in this game looks
## like a bug report. Everything the kids touch gets the same
## rounded clay treatment as the rest of the HUD.
static func _style_button(b: Button) -> void:
	b.add_theme_color_override("font_color", Palette.CREAM)
	b.add_theme_color_override("font_hover_color", Palette.CREAM)
	b.add_theme_color_override("font_pressed_color", Palette.UI_PANEL)
	b.add_theme_color_override("font_focus_color", Palette.CREAM)
	b.add_theme_stylebox_override("normal", _pill(Palette.UI_BUTTON))
	b.add_theme_stylebox_override("hover", _pill(Palette.UI_HOVER))
	b.add_theme_stylebox_override("pressed", _pill(Palette.EARTH_DARK))
	b.add_theme_stylebox_override("focus", _pill(Palette.UI_BUTTON))


static func _style_field(f: LineEdit) -> void:
	f.add_theme_color_override("font_color", Palette.UI_TEXT)
	f.add_theme_color_override("font_placeholder_color", Palette.UI_TEXT_SOFT)
	f.add_theme_color_override("caret_color", Palette.UI_TEXT)
	f.add_theme_stylebox_override("normal", _pill(Palette.UI_PANEL_DIM))
	f.add_theme_stylebox_override("focus", _pill(Palette.CREAM))


static func _pill(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.UI_PANEL
	sb.set_corner_radius_all(18)
	sb.shadow_color = Palette.UI_SHADOW
	sb.shadow_size = 10
	return sb
