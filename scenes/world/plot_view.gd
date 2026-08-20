# =============================================================
# plot_view.gd — one patch of soil, and whatever is growing in it.
# -------------------------------------------------------------
# Pure display. It never decides anything: it asks GameState what
# state its plot is in and rebuilds its clay accordingly. That
# separation is what lets the art be replaced wholesale later
# without touching a single rule of the game.
# =============================================================
class_name PlotView
extends Node3D

var index: int = 0

var _visual: Node3D
var _ready_mark: Node3D
var _crop_node: Node3D
var _t: float = 0.0
var _pop: float = 0.0
var _last_state: int = -1


func refresh() -> void:
	var p: Dictionary = GameState.plots[index]
	var state: int = int(p["state"])
	if _visual:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	_ready_mark = null
	_crop_node = null

	match state:
		GameState.Soil.UNTILLED:
			_build_grass()
		GameState.Soil.TILLED:
			_build_soil(false)
		GameState.Soil.PLANTED:
			_build_soil(false)
			_build_seed_mound()
		GameState.Soil.GROWING:
			_build_soil(true)
			var prog := GameState.plot_progress(index)
			var stage := 0 if prog < 0.45 else 1
			_crop_node = Props.crop(String(p["crop"]), stage)
			_visual.add_child(_crop_node)
		GameState.Soil.READY:
			_build_soil(true)
			_crop_node = Props.crop(String(p["crop"]), 2)
			_visual.add_child(_crop_node)
			_build_ready_mark(String(p["crop"]))

	# A little squash-and-stretch whenever the plot changes — the
	# single cheapest thing that makes a game feel alive.
	if _last_state != state:
		_pop = 1.0
	_last_state = state
	set_process(true)


func _build_grass() -> void:
	# A slightly domed patch of turf with real blades standing up,
	# so untilled plots read as "grass" and not "green plate".
	_visual.add_child(ClayKit.dome(0.98, 0.09, Palette.MOSS.lerp(Palette.MOSS_DARK, 0.35),
		Vector3(0, -0.02, 0), {"segments": 14, "grain": 0.22, "wobble": 0.04, "gloss": 0.0}))
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.4
		var r: float = 0.28 + 0.42 * fmod(float(i) * 0.37, 1.0)
		var h: float = 0.26 + 0.16 * fmod(float(i) * 0.61, 1.0)
		var blade := ClayKit.blob(Vector3(0.2, h, 0.16),
			Palette.MOSS_DARK.lerp(Palette.MOSS_LIGHT, fmod(float(i) * 0.29, 1.0)),
			Vector3(cos(a) * r, 0.10 + h * 0.4, sin(a) * r),
			{"segments": 8, "grain": 0.24})
		blade.rotation_degrees = Vector3(fmod(float(i) * 13.0, 20.0) - 10.0, float(i) * 40.0,
			fmod(float(i) * 17.0, 22.0) - 11.0)
		_visual.add_child(blade)


func _build_soil(watered: bool) -> void:
	var col: Color = Palette.SOIL_WET if watered else Palette.SOIL_DRY
	# A shallow bed, not a loaf.
	_visual.add_child(ClayKit.slab(Vector3(2.0, 0.20, 2.0), col, Vector3(0, 0.0, 0),
		{"segments": 12, "grain": 0.22, "noise_scale": 11.0, "rim": 0.07,
		 "gloss": 0.14 if watered else 0.0}))
	# Furrows: low, wide, barely proud of the bed.
	for i in 3:
		_visual.add_child(ClayKit.blob(Vector3(1.66, 0.06, 0.18), col.lightened(0.035),
			Vector3(0, 0.075, -0.5 + i * 0.5),
			{"segments": 10, "grain": 0.3, "wobble": 0.07, "rim": 0.06}))
	if watered:
		# Dark damp patches soaking in, not beads of water sitting on top.
		for i in 2:
			var a := TAU * float(i) / 2.0 + 0.9
			_visual.add_child(ClayKit.blob(Vector3(0.62, 0.03, 0.52), Palette.SKY_BLUE.darkened(0.42),
				Vector3(cos(a) * 0.42, 0.115, sin(a) * 0.42),
				{"segments": 10, "gloss": 0.9, "alpha": 0.28}))


func _build_seed_mound() -> void:
	_visual.add_child(ClayKit.dome(0.34, 0.14, Palette.SOIL_DRY.darkened(0.16),
		Vector3(0, 0.10, 0), {"segments": 10, "gloss": 0.0}))


func _build_ready_mark(crop_id: String) -> void:
	# World Design §6: every reward moment gets a visual cue.
	var rarity: String = String(Defs.CROPS[crop_id].get("rarity", "common"))
	var glow: Color = Palette.RARITY.get(rarity, Palette.CREAM)
	if rarity == "common":
		glow = Palette.WARM_YELLOW
	_ready_mark = Node3D.new()
	_visual.add_child(_ready_mark)
	for i in 3:
		var a := TAU * float(i) / 3.0
		_ready_mark.add_child(ClayKit.blob(Vector3(0.15, 0.15, 0.15), glow,
			Vector3(cos(a) * 0.55, 1.05, sin(a) * 0.55),
			{"segments": 8, "emission": glow, "emission_strength": 2.6, "rim": 0.45}))


func _process(delta: float) -> void:
	_t += delta
	if _ready_mark:
		_ready_mark.rotation.y += delta * 1.1
		_ready_mark.position.y = 0.06 * sin(_t * 2.2)
	if _crop_node:
		# Gentle breathing so growing crops never look frozen.
		var s: float = 1.0 + 0.025 * sin(_t * 1.6 + float(index))
		_crop_node.scale = Vector3(s, 1.0 + 0.04 * sin(_t * 1.6 + float(index)), s)
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 3.2)
		var e: float = _pop * _pop
		_visual.scale = Vector3(1.0 + 0.22 * e, 1.0 - 0.28 * e, 1.0 + 0.22 * e)
		if _pop <= 0.0:
			_visual.scale = Vector3.ONE
