# =============================================================
# hud.gd — the warm, handmade interface.
# -------------------------------------------------------------
# Art Bible §6: "UI elements look like they were stamped from
# clay." Every panel is a rounded StyleBoxFlat in warm cream with
# a soft drop shadow — no sharp rectangles, no white, no thin
# strokes. Progress bars are clay tubes that fill with colour.
#
# The HUD never changes the game. It listens to GameState signals
# and calls GameState methods. That is the whole contract.
# =============================================================
class_name Hud
extends CanvasLayer

const PAD := 18

var _perf_label: Label
var _perf_accum: float = 0.0
var _roster_panel: PanelContainer
var _roster_box: VBoxContainer
var _coin_label: Label
var _hunger_fill: StyleBoxFlat
var _hunger_bar: ProgressBar
var _hunger_label: Label
var _basket_label: Label
var _seed_row: HBoxContainer
var _material_row: HBoxContainer
var _bag_row: HBoxContainer
var _craft: PanelContainer
var _quest_box: VBoxContainer
var _prompt: PanelContainer
var _prompt_label: Label
var _toast_box: VBoxContainer
var _dialogue: PanelContainer
var _dialogue_who: Label
var _dialogue_text: Label
var _shop: PanelContainer
var _help: PanelContainer
var _dialogue_timer := 0.0
var _root: Control


func _ready() -> void:
	layer = 10
	# Controls need a sized parent to anchor against. One full-rect
	# Control under the CanvasLayer gives every panel a stable frame.
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_coins()
	_build_hunger()
	_build_quests()
	_build_prompt()
	_build_toasts()
	_build_dialogue()
	_build_shop()
	_build_craft()
	_build_help()
	_build_roster()

	Net.roster_changed.connect(_refresh_roster)
	Net.mode_changed.connect(_refresh_roster)
	GameState.roster_or_claims_changed.connect(_refresh_roster)
	GameState.coins_changed.connect(func(v): _coin_label.text = str(v))
	GameState.hunger_changed.connect(_refresh_hunger)
	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.materials_changed.connect(_refresh_inventory)
	GameState.quests_changed.connect(_refresh_quests)
	GameState.toast.connect(show_toast)
	GameState.say.connect(show_dialogue)

	_coin_label.text = str(GameState.coins)
	_refresh_hunger(GameState.hunger)
	_refresh_inventory()
	_refresh_quests()

	# Old Sprout opens the game if this is a new save.
	if GameState.onboarding_index == 0:
		await get_tree().create_timer(0.9).timeout
		var step := GameState.onboarding_step()
		if not step.is_empty():
			show_dialogue(String(step["who"]), String(step["text"]))
			GameState.advance_onboarding_manually()


func _process(delta: float) -> void:
	if _dialogue.visible:
		_dialogue_timer -= delta
		if _dialogue_timer <= 0.0:
			_fade_out(_dialogue)
	_refresh_perf(delta)


## Live fps and draw calls, at the foot of the controls card.
##
## Cheap on purpose: only while the card is actually on screen, and
## only twice a second. A performance readout that costs performance
## is a joke with a long setup.
func _refresh_perf(delta: float) -> void:
	if _perf_label == null or _help == null or not _help.visible:
		return
	_perf_accum += delta
	if _perf_accum < 0.5:
		return
	_perf_accum = 0.0
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_perf_label.text = "%d fps   ·   %d draw calls   ·   %d players" % [
		int(Engine.get_frames_per_second()), calls, Net.player_count()]


# =============================================================
#  Clay-stamped building blocks
# =============================================================
static func clay_panel(bg: Color = Palette.UI_PANEL, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3)
	sb.border_color = Palette.EARTH.lerp(bg, 0.45)
	sb.shadow_color = Palette.UI_SHADOW
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func label(text: String, size: int, col: Color = Palette.UI_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# A soft outline keeps text readable against the world.
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _wrap(control: Control, bg: Color = Palette.UI_PANEL, radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", clay_panel(bg, radius))
	p.add_child(control)
	return p


## Pin a self-sizing panel to a point on the screen.
##
## The trick with a container that sizes itself to its contents:
## collapse the rect to ZERO at the anchor point (all four offsets
## equal), then let grow_horizontal / grow_vertical decide which
## way its minimum size pushes it out. Setting only two offsets
## leaves an inside-out rect and the panel explodes across the
## screen — which is exactly what happened the first time.
func _dock(node: Control, ax: float, ay: float, off: Vector2,
		grow_h: Control.GrowDirection, grow_v: Control.GrowDirection) -> void:
	_root.add_child(node)
	node.anchor_left = ax
	node.anchor_right = ax
	node.anchor_top = ay
	node.anchor_bottom = ay
	node.offset_left = off.x
	node.offset_right = off.x
	node.offset_top = off.y
	node.offset_bottom = off.y
	node.grow_horizontal = grow_h
	node.grow_vertical = grow_v


func _dock_top_left(n: Control) -> void:
	_dock(n, 0.0, 0.0, Vector2(PAD, PAD),
		Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)


func _dock_top_right(n: Control) -> void:
	_dock(n, 1.0, 0.0, Vector2(-PAD, PAD),
		Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)


## Bottom-left is where the belly bar and the basket live -- and on
## a tablet it is also where the thumbstick lands. The panel moves up
## and out of the way rather than the stick moving, because a
## thumbstick anywhere but the bottom corner is uncomfortable to hold
## and a panel is happy anywhere.
func _dock_bottom_left(n: Control) -> void:
	var lift := 232.0 if Controls.wants_touch_ui() else 0.0
	_dock(n, 0.0, 1.0, Vector2(PAD, -PAD - lift),
		Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)


func _dock_bottom_centre(n: Control, up: float) -> void:
	_dock(n, 0.5, 1.0, Vector2(0, -up),
		Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)


func _dock_top_centre(n: Control, down: float) -> void:
	_dock(n, 0.5, 0.0, Vector2(0, down),
		Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)


func _dock_right(n: Control) -> void:
	_dock(n, 1.0, 0.5, Vector2(-PAD, -56),
		Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH)


func _dock_centre(n: Control) -> void:
	_dock(n, 0.5, 0.5, Vector2.ZERO,
		Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)


# =============================================================
#  Who else is here — under the coin purse, top right
# -------------------------------------------------------------
# Hidden entirely in single player. A panel that says "Players: 1"
# is just clutter telling you that you are alone.
# =============================================================
func _build_roster() -> void:
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 2)
	_roster_panel = _wrap(_roster_box, Palette.UI_PANEL_DIM, 12)
	_dock(_roster_panel, 1.0, 0.0, Vector2(-PAD, PAD + 56),
		Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	_roster_panel.visible = false
	_refresh_roster()


func _refresh_roster() -> void:
	if _roster_box == null:
		return
	for c in _roster_box.get_children():
		c.queue_free()
	if Net.is_solo():
		_roster_panel.visible = false
		return
	_roster_panel.visible = true
	var head := label("In the hills", 14, Palette.UI_TEXT_SOFT)
	_roster_box.add_child(head)
	for id in Net.roster:
		var who := Net.name_of(int(id))
		# Their clearing's colour, so the name in this list matches
		# the name floating over the Sprite out in the field.
		var col := Palette.UI_TEXT
		for i in GameState.homestead_owner.size():
			if String(GameState.homestead_owner[i]) == who and who != "":
				col = World.HOMESTEAD_COLOURS[i % World.HOMESTEAD_COLOURS.size()]
		var line := who
		if int(id) == Net.my_id():
			line += "  (you)"
		if int(id) == 1:
			line += "  ★"          # the host, whose machine holds the world
		_roster_box.add_child(label(line, 16, col))


# =============================================================
#  Coins — top right (Art Bible §6 HUD layout)
# =============================================================
func _build_coins() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var coin := _clay_coin_icon()
	row.add_child(coin)
	_coin_label = label("0", 30, Palette.EARTH_DARK)
	row.add_child(_coin_label)
	_dock_top_right(_wrap(row, Palette.UI_PANEL, 22))


func _clay_coin_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(30, 30)
	c.draw.connect(func():
		c.draw_circle(Vector2(15, 15), 14, Palette.WARM_YELLOW.darkened(0.18))
		c.draw_circle(Vector2(15, 14), 12, Palette.WARM_YELLOW)
		c.draw_circle(Vector2(11, 10), 3.5, Color(1, 1, 1, 0.55))
	)
	return c


# =============================================================
#  Hunger — bottom left, a clay tube that fills
# =============================================================
func _build_hunger() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_mushroom_icon())
	_hunger_label = label("Belly  72%", 18, Palette.UI_TEXT)
	top.add_child(_hunger_label)
	col.add_child(top)

	# The clay tube (Art Bible §6: "progress bars styled as clay
	# tubes filling with colour"). A ProgressBar rather than a hand
	# sized ColorRect — containers re-layout their children every
	# frame and would flatten a manually sized rect.
	_hunger_bar = ProgressBar.new()
	_hunger_bar.custom_minimum_size = Vector2(212, 24)
	_hunger_bar.max_value = 100.0
	_hunger_bar.value = 72.0
	_hunger_bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Palette.EARTH.lerp(Palette.UI_PANEL, 0.30)
	back.set_corner_radius_all(12)
	back.set_border_width_all(2)
	back.border_color = Palette.EARTH
	_hunger_bar.add_theme_stylebox_override("background", back)
	_hunger_fill = StyleBoxFlat.new()
	_hunger_fill.bg_color = Palette.CARROT
	_hunger_fill.set_corner_radius_all(12)
	_hunger_bar.add_theme_stylebox_override("fill", _hunger_fill)
	col.add_child(_hunger_bar)

	_basket_label = label("Basket: empty", 15, Palette.UI_TEXT_SOFT)
	col.add_child(_basket_label)

	_seed_row = _labelled_row(col, "Seeds")
	_material_row = _labelled_row(col, "Pouch")
	_bag_row = _labelled_row(col, "Holding")

	_dock_bottom_left(_wrap(col))


## A caption plus a row of chips, e.g.  Seeds  [Carrot x3][Radish x2]
func _labelled_row(parent: VBoxContainer, caption: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var cap := label(caption, 14, Palette.UI_TEXT_SOFT)
	cap.custom_minimum_size.x = 58
	line.add_child(cap)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 5)
	line.add_child(chips)
	parent.add_child(line)
	return chips


## One item. The SELECTED chip is filled with its own colour and dark
## text; the rest are flat and quiet. Bold-vs-normal is not enough to
## spot at a glance, and a glance is all a kid gives it.
func _chip(text: String, tint: Color, active: bool) -> Control:
	var l := label(text, 14, Palette.UI_TEXT if active else Palette.UI_TEXT_SOFT)
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(9)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	if active:
		box.bg_color = tint.lerp(Palette.UI_PANEL, 0.45)
		box.set_border_width_all(2)
		box.border_color = tint.darkened(0.15)
		l.add_theme_color_override("font_color", tint.darkened(0.5))
	else:
		box.bg_color = Palette.UI_PANEL_DIM
		box.set_border_width_all(1)
		box.border_color = Palette.UI_PANEL_DIM.darkened(0.08)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.add_child(l)
	return p


func _mushroom_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(26, 26)
	c.draw.connect(func():
		c.draw_rect(Rect2(10, 12, 6, 12), Palette.CREAM)
		c.draw_circle(Vector2(13, 13), 11, Palette.DEEP_RED)
		c.draw_rect(Rect2(2, 13, 22, 11), Palette.UI_PANEL)
		c.draw_circle(Vector2(13, 12), 11, Palette.DEEP_RED)
		c.draw_circle(Vector2(9, 8), 2.5, Palette.CREAM)
		c.draw_circle(Vector2(17, 11), 2.0, Palette.CREAM)
	)
	return c


func _refresh_hunger(v: float) -> void:
	_hunger_label.text = "Belly  %d%%" % int(round(v))
	_hunger_bar.value = clampf(v, 0.0, 100.0)
	if v <= Defs.HUNGER_PECKISH:
		_hunger_fill.bg_color = Palette.DEEP_RED
		_hunger_label.add_theme_color_override("font_color", Palette.DEEP_RED)
	else:
		_hunger_fill.bg_color = Palette.CARROT
		_hunger_label.add_theme_color_override("font_color", Palette.UI_TEXT)


func _refresh_inventory() -> void:
	var basket: Array = []
	for crop in GameState.larder:
		var n: int = int(GameState.larder[crop])
		if n > 0:
			basket.append("%s x%d" % [Defs.CROPS[crop]["name"], n])
	_basket_label.text = "Basket: " + (", ".join(basket) if basket.size() > 0 else "empty")

	# Seeds — the one in hand is filled in its own crop colour.
	for c in _seed_row.get_children():
		c.queue_free()
	for crop in Defs.plantable_crops():
		_seed_row.add_child(_chip(
			"%s x%d" % [Defs.CROPS[crop]["name"], GameState.seed_count(crop)],
			Defs.CROPS[crop]["color"], crop == GameState.selected_seed))

	# Gathered materials.
	for c in _material_row.get_children():
		c.queue_free()
	var any_mat := false
	for mat in Defs.MATERIALS:
		var n := GameState.material_count(mat)
		if n <= 0:
			continue
		any_mat = true
		_material_row.add_child(_chip("%s x%d" % [Defs.MATERIALS[mat]["name"], n],
			Defs.MATERIALS[mat]["colour"], false))
	if not any_mat:
		_material_row.add_child(label("nothing yet", 14, Palette.UI_TEXT_SOFT))

	# Crafted things waiting to be placed.
	for c in _bag_row.get_children():
		c.queue_free()
	var ids := GameState.placeable_ids()
	if ids.is_empty():
		_bag_row.add_child(label("nothing crafted", 14, Palette.UI_TEXT_SOFT))
	else:
		for id in ids:
			_bag_row.add_child(_chip(
				"%s x%d" % [Defs.RECIPES[id]["name"], GameState.bag_count(id)],
				Palette.UI_ACCENT, id == GameState.selected_build))

	if _shop and _shop.visible:
		_refresh_shop()
	if _craft and _craft.visible:
		_refresh_craft()


# =============================================================
#  Quest tracker — top left
# =============================================================
func _build_quests() -> void:
	_quest_box = VBoxContainer.new()
	_quest_box.add_theme_constant_override("separation", 5)
	var panel := _wrap(_quest_box)
	panel.name = "QuestPanel"
	panel.custom_minimum_size = Vector2(280, 0)
	_dock_top_left(panel)


func _refresh_quests() -> void:
	for c in _quest_box.get_children():
		c.queue_free()
	_quest_box.add_child(label("Tendril Hills", 20, Palette.EARTH_DARK))
	var active := GameState.active_quests()
	if active.is_empty():
		_quest_box.add_child(label("All done — well tended!", 15, Palette.UI_ACCENT))
	for q in active:
		var done := GameState.quest_progress(q)
		var l := label("• %s  (%d/%d)" % [q["text"], done, q["target"]], 15,
			Palette.UI_ACCENT if done >= int(q["target"]) else Palette.UI_TEXT_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 236
		_quest_box.add_child(l)
	var n := GameState.quests_done.size()
	if not GameState.portal_open:
		_quest_box.add_child(label("Root Portal: %d / %d quests" % [n, Defs.PORTAL_QUESTS_REQUIRED],
			14, Palette.SKY_BLUE.darkened(0.35)))
	else:
		_quest_box.add_child(label("The Root Portal is awake.", 14, Palette.SKY_BLUE.darkened(0.35)))


# =============================================================
#  Interaction prompt — bottom centre
# =============================================================
func _build_prompt() -> void:
	_prompt_label = label("", 20, Palette.UI_TEXT)
	_prompt = _wrap(_prompt_label, Palette.UI_PANEL, 20)
	_dock_bottom_centre(_prompt, 104.0)
	_prompt.visible = false


func set_prompt(text: String) -> void:
	if text == "":
		_prompt.visible = false
		return
	_prompt_label.text = "[E]  %s" % text
	_prompt.visible = true


func set_build_prompt(active: bool) -> void:
	if active:
		var id := GameState.selected_build
		var what: String = String(Defs.RECIPES[id]["name"]) if Defs.RECIPES.has(id) else "it"
		var more := "   [2] switch" if GameState.placeable_ids().size() > 1 else ""
		_prompt_label.text = "[E] place %s (x%d)%s   [3] cancel" % [
			what, GameState.bag_count(id), more]
		_prompt.visible = true
	else:
		_prompt.visible = false


# =============================================================
#  Toasts
# =============================================================
func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.custom_minimum_size = Vector2(420, 0)
	_dock_top_centre(_toast_box, 96.0)


func show_toast(text: String, color: Color = Palette.UI_TEXT) -> void:
	var l := label(text, 18, color.darkened(0.25))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := _wrap(l, Palette.UI_PANEL, 16)
	p.modulate.a = 0.0
	_toast_box.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.1)
	tw.tween_property(p, "modulate:a", 0.0, 0.45)
	tw.tween_callback(p.queue_free)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
		break


# =============================================================
#  Dialogue
# =============================================================
func _build_dialogue() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_dialogue_who = label("", 18, Palette.DEEP_RED)
	col.add_child(_dialogue_who)
	_dialogue_text = label("", 19, Palette.UI_TEXT)
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.custom_minimum_size = Vector2(560, 0)
	col.add_child(_dialogue_text)
	_dialogue = _wrap(col, Palette.UI_PANEL, 22)
	_dialogue.pivot_offset = Vector2(300, 40)
	_dock_bottom_centre(_dialogue, 170.0)
	_dialogue.visible = false


func show_dialogue(who: String, text: String) -> void:
	_dialogue_who.text = who
	_dialogue_who.visible = who != ""
	_dialogue_text.text = text
	_dialogue.visible = true
	_dialogue.modulate.a = 1.0
	_dialogue_timer = 5.0 + text.length() * 0.035
	_dialogue.scale = Vector2(0.96, 0.96)
	create_tween().tween_property(_dialogue, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade_out(node: Control) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): node.visible = false)


# =============================================================
#  Market stall
# =============================================================
func _build_shop() -> void:
	var col := VBoxContainer.new()
	col.name = "ShopCol"
	col.add_theme_constant_override("separation", 8)
	_shop = _wrap(col, Palette.UI_PANEL, 24)
	_shop.custom_minimum_size = Vector2(380, 0)
	_dock_centre(_shop)
	_shop.visible = false


func _build_craft() -> void:
	var col := VBoxContainer.new()
	col.name = "CraftCol"
	col.add_theme_constant_override("separation", 4)
	_craft = _wrap(col, Palette.UI_PANEL, 24)
	_craft.custom_minimum_size = Vector2(470, 0)
	_dock_centre(_craft)
	_craft.visible = false


func toggle_craft() -> void:
	_craft.visible = not _craft.visible
	if _craft.visible:
		_shop.visible = false
		_refresh_craft()
		Sfx.play("pop")


func _refresh_craft() -> void:
	var col: VBoxContainer = _craft.get_node("CraftCol")
	for c in col.get_children():
		c.queue_free()
	col.add_child(label("Workbench", 22, Palette.EARTH_DARK))

	var have: Array = []
	for mat in Defs.MATERIALS:
		have.append("%s %d" % [Defs.MATERIALS[mat]["name"], GameState.material_count(mat)])
	col.add_child(label("Pouch:  " + "   ".join(have), 15, Palette.UI_TEXT_SOFT))
	col.add_child(HSeparator.new())

	for id in Defs.RECIPES:
		var r: Dictionary = Defs.RECIPES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_l := label(String(r["name"]), 16, Palette.EARTH_DARK)
		name_l.custom_minimum_size.x = 130
		row.add_child(name_l)

		# Spell out the cost per material, so a child can see WHICH one
		# they are short of rather than just that they cannot have it.
		var cost_line := HBoxContainer.new()
		cost_line.add_theme_constant_override("separation", 6)
		cost_line.custom_minimum_size.x = 190
		for mat in r["cost"]:
			var need: int = int(r["cost"][mat])
			var got := GameState.material_count(mat)
			cost_line.add_child(label("%s %d/%d" % [
				String(Defs.MATERIALS[mat]["name"]).left(4), got, need], 13,
				Palette.UI_ACCENT if got >= need else Palette.UI_WARN))
		row.add_child(cost_line)

		var b := _clay_button("Craft" if GameState.can_craft(id) else "—")
		b.disabled = not GameState.can_craft(id)
		b.custom_minimum_size.x = 78
		b.pressed.connect(func(): GameState.craft(id))
		row.add_child(b)
		col.add_child(row)

		var d := label("   " + String(r.get("desc", "")), 12, Palette.UI_TEXT_SOFT)
		col.add_child(d)

	col.add_child(HSeparator.new())
	var close := _clay_button("Close")
	close.pressed.connect(func(): _craft.visible = false)
	col.add_child(close)


func toggle_shop() -> void:
	_shop.visible = not _shop.visible
	if _shop.visible:
		_craft.visible = false
		_refresh_shop()
		Sfx.play("pop")


func _refresh_shop() -> void:
	var col: VBoxContainer = _shop.get_node("ShopCol")
	for c in col.get_children():
		c.queue_free()
	col.add_child(label("Pip's Seed Stall", 24, Palette.EARTH_DARK))
	col.add_child(label("Coins: %d" % GameState.coins, 16, Palette.UI_TEXT_SOFT))

	for crop in Defs.plantable_crops():
		var d: Dictionary = Defs.CROPS[crop]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_l := label("%s seed" % d["name"], 17,
			Palette.RARITY.get(String(d.get("rarity", "common")), Palette.UI_TEXT).darkened(0.35))
		name_l.custom_minimum_size.x = 150
		row.add_child(name_l)
		row.add_child(label("%d c" % int(d["seed_cost"]), 16, Palette.UI_TEXT_SOFT))
		var b := _clay_button("Buy")
		b.pressed.connect(func(): GameState.buy_seed(crop))
		row.add_child(b)
		col.add_child(row)

	col.add_child(HSeparator.new())
	var sell := _clay_button("Sell basket (%d items)" % GameState.total_larder())
	sell.pressed.connect(func(): GameState.sell_larder())
	col.add_child(sell)
	var close := _clay_button("Close")
	close.pressed.connect(func(): _shop.visible = false)
	col.add_child(close)


func _clay_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Palette.UI_PANEL)
	b.add_theme_color_override("font_hover_color", Palette.UI_PANEL)
	b.add_theme_color_override("font_pressed_color", Palette.UI_PANEL_DIM)
	var normal := clay_panel(Palette.UI_BUTTON, 14)
	normal.shadow_size = 4
	var hover := clay_panel(Palette.UI_HOVER, 14)
	hover.shadow_size = 4
	var pressed := clay_panel(Palette.UI_HOVER.darkened(0.15), 14)
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	return b


# =============================================================
#  Help card
# =============================================================
func _build_help() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.add_child(label("How to tend Tendril Hills", 18, Palette.EARTH_DARK))
	# Two sets, because a card that says "WASD — walk" is worse than
	# no card at all on a tablet -- it tells a kid the game is broken.
	var lines := [
		"Left thumb — walk",
		"Jump — jump",
		"< and > — swing the camera",
		"E — do the obvious thing",
		"   grass → till → plant → water → harvest",
		"Eat — eat from your basket",
		"Seed — switch seed type",
		"E on a toadstool, stone or branch — pick it up",
		"Build — place what you crafted",
		"Pip's stall: buy seeds, sell your basket.",
		"Workbench: turn gathered bits into things to build.",
		"Crops keep growing while the game is closed.",
		"",
		"Walk out to a corner of the map and you will find a clearing",
		"with a name on a signpost. That one is yours — it has its own",
		"soil and room to build. North, south, east and west there are",
		"places thick with stone, branches or toadstools.",
		"Tap this card to hide it.",
	] if Controls.wants_touch_ui() else [
		"WASD / arrows — walk",
		"Space — jump",
		"Q / R — swing the camera",
		"E or click — do the obvious thing",
		"   grass → till → plant → water → harvest",
		"1 — eat from your basket",
		"2 — switch seed type",
		"E on a toadstool, stone or branch — pick it up",
		"3 — place what you crafted    2 — switch which one",
		"Pip's stall: buy seeds, sell your basket.",
		"Workbench: turn gathered bits into things to build.",
		"Crops keep growing while the game is closed.",
		"",
		"Walk out to a corner of the map and you will find a clearing",
		"with a name on a signpost. That one is yours — it has its own",
		"soil and room to build. North, south, east and west there are",
		"places thick with stone, branches or toadstools.",
		"H — hide this card      F9 — start over",
	]
	for line in lines:
		col.add_child(label(line, 13, Palette.UI_TEXT_SOFT))
	# Live performance, at the foot of the card. There is no console on
	# an iPad and no way to pass a flag to it, so this is the only way
	# to answer "is this old thing fast enough" from the device itself.
	# Draw calls matter more than fps here: fps tells you it is slow,
	# draw calls tell you why. See tools/bench.sh.
	col.add_child(HSeparator.new())
	_perf_label = label("", 13, Palette.UI_TEXT_SOFT)
	col.add_child(_perf_label)

	_help = _wrap(col, Palette.UI_PANEL, 22)
	_dock_right(_help)
	# On a tablet there is no H key, so the card itself is the button.
	if Controls.wants_touch_ui():
		_help.mouse_filter = Control.MOUSE_FILTER_STOP
		_help.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
				_help.visible = false
			elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				_help.visible = false)
	# Visible while you find your feet, then it steps out of the way.
	_retire_help()


func _retire_help() -> void:
	await get_tree().create_timer(45.0).timeout
	if _help.visible:
		var tw := create_tween()
		tw.tween_property(_help, "modulate:a", 0.0, 1.2)
		tw.tween_callback(func():
			_help.visible = false
			_help.modulate.a = 1.0
			show_toast("Press H any time for the controls", Palette.UI_TEXT_SOFT))


func toggle_help() -> void:
	_help.visible = not _help.visible


func toggle_quest_panel() -> void:
	var p: Control = _root.get_node("QuestPanel")
	p.visible = not p.visible
