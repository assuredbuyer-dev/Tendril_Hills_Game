# =============================================================
# world.gd — builds Tendril Hills at runtime.
# -------------------------------------------------------------
# Terrain mesh + collision, the golden-afternoon lighting rig,
# the village, the farm, the forest edge, and the dormant Root
# Portal. Layout follows World Design §2.
#
# Everything is generated in code, deterministically, so the
# world is identical every run and lives entirely in Git as text.
# =============================================================
class_name World
extends Node3D

# Grid divisions across the whole world. This is a resolution, not
# a size — it has to move with Terrain.HALF_SIZE or the ground goes
# blocky the moment the map grows. At 168 across 136 m the quads are
# about 0.8 m, same as they have always been.
const TERRAIN_RES := 168

# Physics layer 3. Nothing in the game collides with this — only the
# player's SpringArm3D does. It exists so tall props can push the
# camera out of their own geometry without becoming walls the Sprite
# has to walk around. Adding a blocker never changes how the game plays.
const CAM_BLOCK_LAYER := 4
# Layer 1 is the terrain. Anything the Sprite should bump into goes
# here too, and gets camera collision for free (the arm masks 1|4).
const SOLID_LAYER := 1

var interactables: Array = []    # {pos, kind, index, label, radius}
var _plot_views: Array = []
var _gatherables: Dictionary = {}   # node_id -> Node3D in the world
var _placed_root: Node3D
var _placed_interactables: Array = []
var _portal_veil: MeshInstance3D
var _portal_arch: Node3D
var _rng := RandomNumberGenerator.new()
var _remotes: Dictionary = {}       # peer id -> RemotePlayer


func _ready() -> void:
	_rng.seed = 20260817
	_build_environment()
	_build_terrain()
	_build_village()
	_build_farm()
	_build_portal()
	_build_homesteads()
	_build_forest_edge()
	_build_scatter()
	_rebuild_placed()
	_start_regrow_timer()

	GameState.plot_changed.connect(_on_plot_changed)
	GameState.plots_rebuilt.connect(_on_plots_rebuilt)
	GameState.placed_changed.connect(_rebuild_placed)
	GameState.gathered_changed.connect(_hide_gatherable)
	GameState.portal_unlocked.connect(_open_portal)
	Net.remote_moved.connect(_on_remote_moved)
	Net.remote_left.connect(_on_remote_left)
	Net.roster_changed.connect(_refresh_remote_names)
	GameState.roster_or_claims_changed.connect(_refresh_remote_names)
	if GameState.portal_open:
		_open_portal()


# =============================================================
#  Lighting & sky — Art Bible §7: "late afternoon golden light,
#  soft shadows, no harsh contrast."
# =============================================================
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("8FC3DE")
	sky_mat.sky_horizon_color = Color("F6E3C4")
	sky_mat.sky_curve = 0.18
	sky_mat.ground_bottom_color = Color("C9B08A")
	sky_mat.ground_horizon_color = Color("F0DFC0")
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.70
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.7
	env.fog_enabled = true
	env.fog_light_color = Palette.FOG_COLOR
	env.fog_light_energy = 0.6
	# The world is twice as deep as it was, so distance has to do more
	# work. Fog is also what hides the point where far scenery stops
	# being drawn (see _fade) — turn one down and you must turn the
	# other up, or trees start popping into existence in clear air.
	env.fog_density = 0.0040
	env.fog_sun_scatter = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.16
	env.adjustment_contrast = 1.07

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Palette.SUN_COLOR
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-38, 128, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Shadows are the single most expensive thing here: every object
	# inside this radius is drawn a SECOND time into the shadow map,
	# so this number costs more draw calls than anything else on this
	# page. Pulling it in from 70 to 58 while the world doubled is
	# what kept the bigger map affordable — and by 58 m the fog has
	# taken most of the contrast out of a shadow anyway.
	sun.directional_shadow_max_distance = 58.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.4
	sun.light_specular = 0.15
	add_child(sun)

	# A cool bounce from the opposite side keeps shadows from going
	# muddy — the classic two-light setup for stop-motion sets.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Palette.AMBIENT_SKY
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-28, -52, 0)
	fill.shadow_enabled = false
	add_child(fill)


# =============================================================
#  Terrain
# =============================================================
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var size := Terrain.HALF_SIZE * 2.0
	var step := size / float(TERRAIN_RES)
	var patch := FastNoiseLite.new()
	patch.seed = 991
	patch.frequency = 0.09

	var verts: Array = []
	for i in TERRAIN_RES + 1:
		var row: Array = []
		for j in TERRAIN_RES + 1:
			var x := -Terrain.HALF_SIZE + j * step
			var z := -Terrain.HALF_SIZE + i * step
			row.append(Terrain.point(x, z))
		verts.append(row)

	for i in TERRAIN_RES:
		for j in TERRAIN_RES:
			var a: Vector3 = verts[i][j]
			var b: Vector3 = verts[i][j + 1]
			var c: Vector3 = verts[i + 1][j + 1]
			var d: Vector3 = verts[i + 1][j]
			_tri(st, patch, a, b, c)
			_tri(st, patch, a, c, d)

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = ClayKit.material(Color.WHITE, {
		"wobble": 0.0,          # terrain already has its own relief
		"grain": 0.13,
		"noise_scale": 2.2,
		"rim": 0.05,
		"vertex_color": 1.0,
	})
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)


func _tri(st: SurfaceTool, patch: FastNoiseLite, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_color(_ground_color(v, patch))
		st.add_vertex(v)


func _ground_color(v: Vector3, patch: FastNoiseLite) -> Color:
	var n := patch.get_noise_2d(v.x, v.z) * 0.5 + 0.5
	var col: Color = Palette.MOSS_DARK.lerp(Palette.MOSS_LIGHT, n)
	# Worn earth on the village circle and around the paths.
	var d := Vector2(v.x, v.z).length()
	var worn: float = 1.0 - smoothstep(2.6, 6.4, d)
	col = col.lerp(Palette.CLAY_TAN, worn * 0.55)
	# Darker, richer soil across the farm zone (World Design §2).
	var fx: float = absf(v.x - Terrain.FARM_CENTRE.x) - Terrain.FARM_HALF.x
	var fz: float = absf(v.z - Terrain.FARM_CENTRE.z) - Terrain.FARM_HALF.y
	var farm: float = 1.0 - smoothstep(-1.0, 2.5, maxf(fx, fz))
	col = col.lerp(Palette.SOIL_DRY, farm * 0.5)
	# Each homestead's turf leans toward that player's accent colour,
	# and its soil patch goes dark like the shared farm. From the top
	# of a hill you can tell whose clearing you are looking at.
	for hi in Terrain.HOMESTEADS.size():
		var hp: Vector3 = Terrain.HOMESTEADS[hi]["pos"]
		var hd := Vector2(v.x - hp.x, v.z - hp.z).length()
		var near: float = 1.0 - smoothstep(0.0, Terrain.HOMESTEAD_RADIUS + 2.0, hd)
		if near <= 0.0:
			continue
		# Strong enough to see from the next hill, weak enough that
		# the grass is still grass. Turned up twice already; if you
		# turn it up again, check it from a distance, not from on top
		# of it, or you will end up with a purple field.
		col = col.lerp(HOMESTEAD_COLOURS[hi % HOMESTEAD_COLOURS.size()], near * 0.34)
		var hf: Vector3 = Terrain.HOMESTEADS[hi]["farm"]
		var gx: float = absf(v.x - hf.x) - Terrain.HOMESTEAD_FARM_HALF.x
		var gz: float = absf(v.z - hf.z) - Terrain.HOMESTEAD_FARM_HALF.y
		var patch_f: float = 1.0 - smoothstep(-1.0, 2.5, maxf(gx, gz))
		col = col.lerp(Palette.SOIL_DRY, patch_f * 0.5)

	# The pockets get their own ground, so you can tell what a place
	# gives you before you are standing in it.
	for pk in POCKETS:
		var pc: Vector2 = pk["pos"]
		var pdist := Vector2(v.x - pc.x, v.z - pc.y).length()
		var inside: float = 1.0 - smoothstep(0.0, float(pk["radius"]) + 4.0, pdist)
		if inside <= 0.0:
			continue
		var w: Vector3 = pk["weights"]
		var tint: Color = Palette.MOSS_DARK
		if w.y >= 0.5:
			tint = Palette.STONE            # bare, scraped rock
		elif w.z >= 0.5:
			tint = Palette.EARTH_DARK       # leaf litter under the grove
		else:
			tint = Palette.SOIL_WET         # damp fen ground
		col = col.lerp(tint, inside * 0.45)

	# Cool moss creeping toward the portal.
	var pd := Vector3(v.x, 0, v.z).distance_to(Terrain.PORTAL_POS)
	col = col.lerp(Palette.SKY_BLUE, (1.0 - smoothstep(3.0, 9.0, pd)) * 0.18)
	# Height tint: hilltops catch more sun.
	col = col.lerp(Palette.MOSS_LIGHT, clampf(v.y * 0.12, 0.0, 0.3))
	return col


# =============================================================
#  Village centre
# =============================================================
func _build_village() -> void:
	var landmark := Props.landmark_mushroom()
	_blocker(landmark, 3.2, 9.0)          # cap, for the camera
	_solid(landmark, 1.1, 3.4)            # stem, for the Sprite
	_place(landmark, 0.0, 0.0, 12.0)

	var board := Props.quest_board()
	_blocker(board, 0.8, 2.2)
	_solid(board, 0.0, 0.0, Vector3(2.3, 2.2, 0.5))
	_place(board, -4.6, 3.4, 118.0)
	_register(Vector3(-4.6, 0, 3.4), "board", -1, "Read the quest board", 2.6)

	var stall := Props.market_stall()
	_blocker(stall, 1.9, 2.4)
	_solid(stall, 0.0, 0.0, Vector3(3.7, 1.3, 1.6))
	_place(stall, 5.4, 2.2, -152.0)
	_register(Vector3(5.4, 0, 2.2), "stall", -1, "Trade with Pip", 3.2)

	var sprout := Props.old_sprout()
	_solid(sprout, 0.5, 1.9)
	_place(sprout, 1.6, 9.4, 172.0)
	_register(Vector3(1.6, 0, 9.4), "sprout", -1, "Talk to Old Sprout", 2.8)

	var bench := Props.workbench()
	_solid(bench, 0.0, 0.0, Vector3(2.2, 1.1, 1.3))
	_blocker(bench, 1.3, 1.4)
	_place(bench, 5.0, -2.6, 24.0)
	_register(Vector3(5.0, 0, -2.6), "bench", -1, "Craft at the workbench", 2.9)

	# Welcome sign at the spawn point
	_place(Props.sign_post(Vector3.ZERO, 8.0), -1.8, 12.4, 0.0)

	# Cobble ring around the landmark (Art Bible §7)
	for i in 26:
		var a := TAU * float(i) / 26.0
		var r := 4.5 + sin(a * 3.0) * 0.25
		var s := 0.55 + 0.2 * fmod(float(i) * 0.37, 1.0)
		var stone := ClayKit.blob(Vector3(s, 0.22, s * 0.86),
			Palette.STONE.lerp(Palette.CLAY_TAN, fmod(float(i) * 0.21, 1.0)),
			Vector3.ZERO, {"segments": 10, "grain": 0.2})
		_place(stone, cos(a) * r, sin(a) * r, float(i) * 23.0, 0.02)

	# Worn clay path east toward the farm
	_path(Vector3(6.0, 0, 1.0), Vector3(11.5, 0, 1.0), 9)
	# ...and west toward the portal
	_path(Vector3(-6.0, 0, 0.0), Vector3(-14.5, 0, -1.5), 12)


func _path(from: Vector3, to: Vector3, steps: int) -> void:
	for i in steps:
		var t := float(i) / float(steps - 1)
		var p := from.lerp(to, t)
		var jitter := _rng.randf_range(-0.5, 0.5)
		var s := _rng.randf_range(0.8, 1.25)
		var stone := ClayKit.blob(Vector3(s, 0.2, s * 0.8), Palette.CLAY_TAN.darkened(0.05),
			Vector3.ZERO, {"segments": 10, "grain": 0.22})
		_place(stone, p.x, p.z + jitter, _rng.randf_range(0, 360), 0.01)


# =============================================================
#  Farm zone
# =============================================================
func _build_farm() -> void:
	for i in GameState.plots.size():
		var view := PlotView.new()
		view.index = i
		view.position = GameState.plot_position(i)
		add_child(view)
		view.refresh()
		_plot_views.append(view)
		_register(view.position, "plot", i, "", 1.45)

	# Fence around the farm, with a gap facing the village
	var half := Terrain.FARM_HALF + Vector2(1.4, 1.4)
	var c := Terrain.FARM_CENTRE
	var perimeter: Array = []
	var n_x := int(half.x * 2.0 / 1.5)
	var n_z := int(half.y * 2.0 / 1.5)
	for i in n_x + 1:
		var x: float = c.x - half.x + i * (half.x * 2.0 / n_x)
		perimeter.append(Vector2(x, c.z - half.y))
		perimeter.append(Vector2(x, c.z + half.y))
	for i in n_z + 1:
		var z: float = c.z - half.y + i * (half.y * 2.0 / n_z)
		perimeter.append(Vector2(c.x - half.x, z))
		perimeter.append(Vector2(c.x + half.x, z))
	for p in perimeter:
		# Leave a gate on the village-facing (west) side
		if absf(p.x - (c.x - half.x)) < 0.1 and absf(p.y - c.z) < 2.2:
			continue
		var post := Props.fence_post(_rng.randf_range(0.9, 1.1))
		_solid(post, 0.24, 1.0)
		_place(post, p.x, p.y, _rng.randf_range(-8, 8))

	# Watering trough for flavour (World Design §2)
	var trough := Node3D.new()
	trough.add_child(ClayKit.slab(Vector3(1.8, 0.55, 0.9), Palette.EARTH, Vector3(0, 0.27, 0)))
	trough.add_child(ClayKit.slab(Vector3(1.5, 0.18, 0.62), Palette.SKY_BLUE, Vector3(0, 0.5, 0),
		{"gloss": 0.75, "wobble": 0.008}))
	_solid(trough, 0.0, 0.0, Vector3(1.9, 0.6, 1.0))
	_place(trough, c.x - half.x - 1.2, c.z + 3.4, 12.0)


# =============================================================
#  Root Portal
# =============================================================
func _build_portal() -> void:
	var portal := Props.root_portal()
	_blocker(portal, 2.8, 5.2)
	_place(portal, Terrain.PORTAL_POS.x, Terrain.PORTAL_POS.z, 90.0)
	_portal_veil = portal.get_node("Veil")
	_portal_arch = portal.get_node("Arch")
	_register(Terrain.PORTAL_POS, "portal", -1, "Examine the root archway", 3.4)

	# Cool accent light — "cool blue-green even before activation"
	var glow := OmniLight3D.new()
	glow.light_color = Color("6FC7C0")
	glow.light_energy = 0.7
	glow.omni_range = 11.0
	glow.position = Terrain.point(Terrain.PORTAL_POS.x, Terrain.PORTAL_POS.z) + Vector3(0, 2.4, 0)
	glow.name = "PortalGlow"
	add_child(glow)


func _open_portal() -> void:
	if _portal_veil == null:
		return
	var mat := _portal_veil.material_override as ShaderMaterial
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.0, 0.72, 2.5)
	tw.tween_method(func(v: float): mat.set_shader_parameter("emission_strength", v), 0.0, 2.2, 2.5)
	if _portal_arch:
		for child in _portal_arch.get_children():
			var m := (child as MeshInstance3D).material_override as ShaderMaterial
			m.set_shader_parameter("emission_color", Color("6FC7C0"))
			create_tween().tween_method(
				func(v: float): m.set_shader_parameter("emission_strength", v), 0.0, 0.9, 2.5)


# =============================================================
#  The other players
# -------------------------------------------------------------
# Puppets, created the first time we hear from somebody and freed
# when they leave. Nothing here decides anything -- see
# remote_player.gd.
# =============================================================
func _on_remote_moved(id: int, pos: Vector3, yaw: float, hop: bool) -> void:
	if id == Net.my_id():
		return
	if not _remotes.has(id):
		var rp := RemotePlayer.new()
		rp.setup(id, Net.name_of(id), _colour_for_player(id))
		add_child(rp)
		rp.global_position = pos
		_remotes[id] = rp
	(_remotes[id] as RemotePlayer).move_to(pos, yaw, hop)


func _on_remote_left(id: int) -> void:
	if _remotes.has(id):
		(_remotes[id] as Node).queue_free()
		_remotes.erase(id)


func _refresh_remote_names() -> void:
	for id in _remotes:
		var rp: RemotePlayer = _remotes[id]
		rp.set_display_name(Net.name_of(int(id)))


## A player wears the colour of the clearing they claimed. Before
## they claim one they are cream, like the mushroom stems.
func _colour_for_player(id: int) -> Color:
	var who := Net.name_of(id)
	for i in GameState.homestead_owner.size():
		if String(GameState.homestead_owner[i]) == who and who != "":
			return HOMESTEAD_COLOURS[i % HOMESTEAD_COLOURS.size()]
	return Palette.CREAM


# =============================================================
#  Homesteads — one clearing per player
# =============================================================
# The layout lives in Terrain.HOMESTEADS. This function only
# dresses what is already carved into the ground: a signpost with
# the name on it, a low ring of stones so the clearing reads as
# somewhere rather than just flat, and a path stone pointing home.
#
# Deliberately almost empty. The whole point of a homestead is
# that the player fills it.
func _build_homesteads() -> void:
	for i in Terrain.HOMESTEADS.size():
		var hs: Dictionary = Terrain.HOMESTEADS[i]
		var c: Vector3 = hs["pos"]
		var hue: Color = HOMESTEAD_COLOURS[i % HOMESTEAD_COLOURS.size()]

		# The signpost, with the name on the board. Faces the village,
		# so walking out to your own patch you read your name as you
		# arrive rather than after you have walked past it.
		var post := Props.named_sign(String(hs["name"]),
			Palette.CREAM.lerp(hue, 0.30))
		_solid(post, 0.3, 1.8)
		# Rotating a node by yaw sends its local +Z to (sin y, cos y),
		# and the board's readable face is its +Z. So aiming the sign
		# at the village is atan2 of the vector TO the village, and
		# no half-turn on top of it. Getting this wrong points every
		# signpost out into the trees, which is easy to miss because
		# the back of a sign looks like a sign.
		var facing := rad_to_deg(atan2(-c.x, -c.z))
		_place(post, c.x, c.z, facing)
		_register(Vector3(c.x, 0, c.z), "homestead", i,
			"Read the %s signpost" % String(hs["name"]), 2.2)

		# A ring of low stones. Not a fence — a fence says keep out,
		# and this is the opposite of that.
		for j in 14:
			var a := TAU * float(j) / 14.0 + float(i) * 0.4
			# Leave the village-facing quarter open as a way in.
			var to_village := atan2(-c.z, -c.x)
			if absf(wrapf(a - to_village, -PI, PI)) < 0.55:
				continue
			var stone := Props.path_stone()
			stone.scale = Vector3.ONE * _rng.randf_range(0.8, 1.25)
			_fade(stone, 60.0)
			_place(stone, c.x + cos(a) * Terrain.HOMESTEAD_RADIUS,
				c.z + sin(a) * Terrain.HOMESTEAD_RADIUS, _rng.randf_range(0, 360))


# One accent colour per homestead, in HOMESTEADS order, so each
# kid's signpost is recognisable from across the valley.
const HOMESTEAD_COLOURS := [
	Palette.DEEP_RED, Palette.WARM_YELLOW, Palette.SKY_BLUE, Palette.SOFT_PURPLE,
]


# =============================================================
#  Resource pockets
# =============================================================
# Four times the land is only better if there is a reason to walk
# across it. Scatter spread evenly over a map this size just means
# a longer walk to the same handful of things.
#
# So the materials are not spread evenly. Each pocket below is a
# place that is generous with ONE thing and stingy with the rest,
# sitting on an axis between two homesteads. Need stone? You go
# north. That is the difference between a big map and a map worth
# crossing.
#
# `weights` are toadstool / stone / branch. Edit freely — this is
# the whole design, and it is five lines of data.
# How far away scenery stops being drawn. Trees are big and read as
# landmarks, so they survive to the far side of the map; ankle-height
# clutter does not need to. See _fade for why these and fog_density
# are one setting in two places.
const TREE_FADE := 72.0
const CLUTTER_FADE := 44.0
const COPSE_COUNT := 16


const POCKETS := [
	{"name": "Stonefall",   "pos": Vector2(0.0, -46.0), "radius": 12.0,
	 "count": 46, "weights": Vector3(0.08, 0.78, 0.14)},
	{"name": "Long Grove",  "pos": Vector2(46.0, 0.0),  "radius": 12.0,
	 "count": 46, "weights": Vector3(0.16, 0.10, 0.74)},
	{"name": "Toadfen",     "pos": Vector2(0.0, 46.0),  "radius": 12.0,
	 "count": 46, "weights": Vector3(0.76, 0.12, 0.12)},
	{"name": "Old Quarry",  "pos": Vector2(-46.0, 0.0), "radius": 12.0,
	 "count": 46, "weights": Vector3(0.10, 0.55, 0.35)},
]


# =============================================================
#  Forest edge & scatter
# =============================================================
func _build_forest_edge() -> void:
	# A ring, so the count scales with circumference, not area — the
	# forest is a border, and a border twice as far out needs twice
	# as many trees, not four times.
	var count := int(120.0 * Terrain.HALF_SIZE / 34.0)
	for i in count:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(Terrain.HALF_SIZE - 13.0, Terrain.HALF_SIZE - 1.0)
		var x := cos(a) * r
		var z := sin(a) * r
		# The ring passes right through the outer edge of the
		# homesteads. A tree in the middle of the clearing you were
		# given is not charming, it is in the way.
		if _in_pocket_or_homestead(x, z):
			continue
		# Trees DO block the camera — but only because player.gd now
		# enforces a minimum arm length. Without that floor these same
		# blockers collapsed the lens onto the back of the Sprite's
		# head near the treeline; without the blockers at all, the
		# canopy sat in front of the Sprite instead. The floor is what
		# makes generous blockers safe.
		var tree_scale := _rng.randf_range(0.75, 1.35)
		var t := Props.tree(tree_scale, _rng.randf())
		_blocker(t, 1.5 * tree_scale, 6.5 * tree_scale)   # canopy: camera only
		_solid(t, 0.55 * tree_scale, 3.6 * tree_scale)    # trunk: the Sprite
		_fade(t, TREE_FADE)
		_place(t, x, z, _rng.randf_range(0, 360))

	# A denser wall to the north, per the zone map
	for i in int(34.0 * Terrain.HALF_SIZE / 34.0):
		var x := _rng.randf_range(-Terrain.HALF_SIZE * 0.7, Terrain.HALF_SIZE * 0.7)
		var z := _rng.randf_range(-Terrain.HALF_SIZE * 0.76, -Terrain.HALF_SIZE * 0.53)
		if Vector2(x, z).length() < 15.0:
			continue
		if _in_pocket_or_homestead(x, z):
			continue
		var s_wall := _rng.randf_range(0.85, 1.3)
		var t_wall := Props.tree(s_wall, _rng.randf())
		_blocker(t_wall, 1.5 * s_wall, 6.5 * s_wall)
		_solid(t_wall, 0.55 * s_wall, 3.6 * s_wall)
		_fade(t_wall, TREE_FADE)
		_place(t_wall, x, z, _rng.randf_range(0, 360))

	# Loose copses out in the open ground, so crossing the map is not
	# a featureless field with a wall of trees at the far end. These
	# are also what give the Long Grove its name.
	for i in COPSE_COUNT:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(18.0, Terrain.HALF_SIZE - 16.0)
		var cx := cos(a) * r
		var cz := sin(a) * r
		if _in_pocket_or_homestead(cx, cz):
			continue
		for _j in _rng.randi_range(2, 5):
			var tx := cx + _rng.randf_range(-4.0, 4.0)
			var tz := cz + _rng.randf_range(-4.0, 4.0)
			var sc := _rng.randf_range(0.7, 1.2)
			var ct := Props.tree(sc, _rng.randf())
			_blocker(ct, 1.5 * sc, 6.5 * sc)
			_solid(ct, 0.55 * sc, 3.6 * sc)
			_fade(ct, TREE_FADE)
			_place(ct, tx, tz, _rng.randf_range(0, 360))


func _build_scatter() -> void:
	var flower_colors := [Palette.WARM_YELLOW, Palette.SKY_BLUE, Palette.DEEP_RED,
		Palette.SOFT_PURPLE, Palette.CREAM]
	# Pickups get their own counter, NOT the loop index. The loop skips
	# positions, so its index would shift the moment the scatter rules
	# change and every id in an existing save would point at the wrong
	# bush. This counter only advances when a pickup is actually made.
	var gid := 0

	# Scales with area, because this is a field, not a border. The
	# density stays what it always was; there is simply more field.
	var scatter_n := int(240.0 * pow(Terrain.HALF_SIZE / 34.0, 2.0))
	for i in scatter_n:
		var x := _rng.randf_range(-Terrain.HALF_SIZE + 4.0, Terrain.HALF_SIZE - 4.0)
		var z := _rng.randf_range(-Terrain.HALF_SIZE + 4.0, Terrain.HALF_SIZE - 4.0)
		var d := Vector2(x, z).length()
		if d > Terrain.HALF_SIZE - Terrain.RIM_BAND + 4.0:
			continue
		# A homestead clearing is the player's to fill, not mine.
		if Terrain.homestead_at(x, z) >= 0:
			continue
		# Keep the farm and the village circle clear.
		if absf(x - Terrain.FARM_CENTRE.x) < Terrain.FARM_HALF.x + 2.0 \
		and absf(z - Terrain.FARM_CENTRE.z) < Terrain.FARM_HALF.y + 2.0:
			continue
		if d < 5.4:
			continue

		var roll := _rng.randf()
		if roll < 0.30:
			var fl := Props.flower_cluster(flower_colors[_rng.randi() % flower_colors.size()])
			_fade(fl, CLUTTER_FADE)
			_place(fl, x, z, _rng.randf_range(0, 360))
		elif roll < 0.52:
			gid = _drop_material("toadstool", x, z, gid)
		elif roll < 0.72:
			gid = _drop_material("stone", x, z, gid)
		elif roll < 0.88:
			gid = _drop_material("branch", x, z, gid)
		else:
			var tuft := ClayKit.blob(Vector3(_rng.randf_range(0.5, 1.0), 0.24,
				_rng.randf_range(0.4, 0.8)), Palette.MOSS_DARK, Vector3.ZERO,
				{"segments": 8, "grain": 0.22})
			_fade(tuft, CLUTTER_FADE)
			_place(tuft, x, z, _rng.randf_range(0, 360), 0.04)

	# Branches cluster under the trees, which is where you would look.
	for i in int(34.0 * Terrain.HALF_SIZE / 34.0):
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(Terrain.HALF_SIZE - 16.0, Terrain.HALF_SIZE - 12.0)
		gid = _drop_material("branch", cos(a) * r, sin(a) * r, gid)

	# And the pockets, which is the whole reason the map is worth
	# walking across. See the comment on POCKETS.
	for pk in POCKETS:
		gid = _build_pocket(pk, gid)


## One material pickup, sculpted to match what it is. The three
## kinds all go through here so the scatter and the pockets cannot
## drift apart — add a fourth material and both get it at once.
func _drop_material(kind: String, x: float, z: float, gid: int) -> int:
	var node: Node3D
	match kind:
		"toadstool":
			node = Props.tiny_mushroom(Vector3.ZERO, _rng.randf_range(0.9, 1.8), gid)
		"stone":
			node = Props.rock(_rng.randf_range(0.4, 0.9),
				Palette.STONE.lerp(Palette.MOSS_DARK, _rng.randf() * 0.4))
		_:
			node = Props.branch(gid)
	_fade(node, CLUTTER_FADE)
	_gatherable(node, gid, kind, x, z, _rng.randf_range(0, 360))
	return gid + 1


## A place that is generous with one thing. Scatters `count` pickups
## in a disc, drawn from the pocket's weights, plus a few boulders or
## trees so it looks like somewhere before you know what it gives.
func _build_pocket(pk: Dictionary, gid: int) -> int:
	var c: Vector2 = pk["pos"]
	var radius: float = float(pk["radius"])
	var w: Vector3 = pk["weights"]
	var total: float = w.x + w.y + w.z
	for i in int(pk["count"]):
		# sqrt keeps the disc evenly covered instead of piling
		# everything into the middle.
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		if Vector2(x, z).length() > Terrain.HALF_SIZE - Terrain.RIM_BAND + 2.0:
			continue
		var roll := _rng.randf() * total
		var kind := "toadstool"
		if roll > w.x:
			kind = "stone"
		if roll > w.x + w.y:
			kind = "branch"
		gid = _drop_material(kind, x, z, gid)

	# Landmark geometry, so you can see the pocket from a distance
	# and go "what's over there" rather than stumbling into it.
	var stony: bool = w.y >= 0.5
	for i in 7:
		var a := _rng.randf_range(0.0, TAU)
		var r := sqrt(_rng.randf()) * radius * 0.9
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		if stony:
			var boulder := Props.rock(_rng.randf_range(1.4, 2.6),
				Palette.STONE.lerp(Palette.EARTH_DARK, _rng.randf() * 0.35))
			_solid(boulder, 1.0, 1.6)
			_fade(boulder, TREE_FADE)
			_place(boulder, x, z, _rng.randf_range(0, 360))
		else:
			var sc := _rng.randf_range(1.0, 1.5)
			var t := Props.tree(sc, _rng.randf())
			_blocker(t, 1.5 * sc, 6.5 * sc)
			_solid(t, 0.55 * sc, 3.6 * sc)
			_fade(t, TREE_FADE)
			_place(t, x, z, _rng.randf_range(0, 360))
	return gid


## Somewhere the generic scatter and the tree walls should keep out
## of, because something deliberate is already there.
func _in_pocket_or_homestead(x: float, z: float) -> bool:
	if Terrain.homestead_at(x, z) >= 0:
		return true
	for pk in POCKETS:
		var c: Vector2 = pk["pos"]
		if Vector2(x - c.x, z - c.y).length() < float(pk["radius"]) + 3.0:
			return true
	return false


## A pickup: registered as an interactable, hidden if the save says it
## has already been taken and has not regrown yet.
func _gatherable(node: Node3D, id: int, material: String,
		x: float, z: float, yaw: float) -> void:
	_place(node, x, z, yaw)
	_gatherables[id] = node
	if GameState.is_gathered(id):
		node.visible = false
	interactables.append({
		"pos": Terrain.point(x, z), "kind": "gather", "index": id,
		"label": "Pick up the %s" % String(Defs.MATERIALS[material]["name"]).to_lower(),
		"radius": 1.6, "material": material,
	})


## A hive that has just filled should look full without waiting for
## the player to do anything. Cheap check: only runs on the 1s tick,
## and only rebuilds when a hive actually crosses the line.
var _hive_full: Dictionary = {}

func _refresh_hives() -> void:
	var changed := false
	for i in GameState.placed.size():
		if String(GameState.placed[i]["id"]) != "hive":
			continue
		var full := GameState.hive_progress(i) >= 1.0
		if bool(_hive_full.get(i, false)) != full:
			_hive_full[i] = full
			changed = true
	if changed:
		_rebuild_placed()


## Something was picked -- or grew back. One handler for both, because
## in multiplayer the picking might have been somebody else and the
## regrowing is always the host, so this node cannot assume it was us.
func _hide_gatherable(node_id: int) -> void:
	if not _gatherables.has(node_id):
		return
	var n: Node3D = _gatherables[node_id]
	if GameState.is_gathered(node_id):
		# A small pop rather than a blink — it reads as being picked.
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3(1.25, 0.6, 1.25), 0.08)
		tw.tween_property(n, "scale", Vector3.ZERO, 0.12)
		tw.tween_callback(func():
			n.visible = false
			n.scale = Vector3.ONE)
	else:
		n.visible = true
		n.scale = Vector3.ZERO
		create_tween().tween_property(n, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Slow tick: put back anything whose regrow time has passed. Scenery,
## not physics — once a second is plenty and costs nothing.
func _start_regrow_timer() -> void:
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	# Only the host expires pickups, and it tells everyone. If each
	# machine ran its own timer they would disagree about the exact
	# second a mushroom came back, and two kids would see different
	# meadows. The reveal itself happens in _hide_gatherable, off the
	# gathered_changed signal, so it looks the same wherever it began.
	t.timeout.connect(func():
		_refresh_hives()
		GameState._host_regrow())
	add_child(t)


# =============================================================
#  Everything the player has built
# =============================================================
func _rebuild_placed() -> void:
	if _placed_root and is_instance_valid(_placed_root):
		_placed_root.queue_free()
	_placed_root = Node3D.new()
	_placed_root.name = "Placed"
	add_child(_placed_root)
	_placed_interactables.clear()

	var caps := [Palette.DEEP_RED, Palette.CARROT, Palette.SOFT_PURPLE, Palette.WARM_YELLOW]
	var houses_seen := 0

	for i in GameState.placed.size():
		var item: Dictionary = GameState.placed[i]
		var id := String(item["id"])
		if not Defs.RECIPES.has(id):
			continue                                   # a recipe that no longer exists
		var r: Dictionary = Defs.RECIPES[id]
		# Two craftables need a value passed in; everything else — including
		# anything the kids add — goes through the generic lookup.
		var node: Node3D
		match id:
			"house":
				node = Props.mushroom_house(caps[houses_seen % caps.size()])
				houses_seen += 1
			"hive":
				node = Props.hive(GameState.hive_progress(i) >= 1.0)
			_:
				node = Props.build(String(r.get("build", "")))
		if node == null:
			continue

		if r.has("solid"):
			_solid(node, float(r["solid"][0]), float(r["solid"][1]))
		if r.has("block"):
			_blocker(node, float(r["block"][0]), float(r["block"][1]))

		node.name = "Built%d" % i
		_placed_root.add_child(node)
		node.position = Terrain.point(float(item["x"]), float(item["z"]))
		node.rotation_degrees.y = float(item["yaw"])

		# Some things you can walk up to and use.
		if r.has("act"):
			_placed_interactables.append({
				"pos": node.position, "kind": String(r["act"]), "index": i,
				"label": String(r["name"]), "radius": 2.2,
			})


# =============================================================
#  Helpers
# =============================================================
## Give a prop an invisible cylinder the camera arm can bump into.
## Radius and height are deliberately coarse — this is an occluder, not
## a hitbox, and a rough shape reads better than an exact one (no
## snagging on a mushroom's gill).
## Give a prop a body the SPRITE bumps into (and the camera, for free).
## Use this for anything taller than a knee. Ankle-height scenery stays
## walk-through — a cozy game where you snag on every pebble is worse
## than one you can stroll through.
func _solid(node: Node3D, radius: float, height: float, box: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	if box != Vector3.ZERO:
		var b := BoxShape3D.new()
		b.size = box
		col.shape = b
		col.position = Vector3(0, box.y * 0.5, 0)
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = height
		col.shape = cyl
		col.position = Vector3(0, height * 0.5, 0)
	body.add_child(col)
	node.add_child(body)


func _blocker(node: Node3D, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "CamBlock"
	body.collision_layer = CAM_BLOCK_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	col.shape = cyl
	col.position = Vector3(0, height * 0.5, 0)
	body.add_child(col)
	node.add_child(body)


func _place(node: Node3D, x: float, z: float, yaw_deg: float, y_offset: float = 0.0) -> void:
	node.position = Terrain.point(x, z) + Vector3(0, y_offset, 0)
	node.rotation_degrees.y = yaw_deg
	add_child(node)


## Stop drawing this prop past `dist` metres.
##
## This is the whole reason the map could get four times bigger
## without the frame rate falling over. Every prop here is a little
## cluster of separate mesh instances — a tree is a trunk plus five
## leaf blobs — and each one is a draw call whether it fills the
## screen or is a speck on the far hill. Quadrupling the land while
## drawing all of it would have quadrupled that bill.
##
## Hard cutoff, no fade: fading an object out needs transparency,
## and the clay shader is deliberately opaque (a shader that writes
## ALPHA turns ALL of its geometry see-through). Fog is what hides
## the cutoff instead, which is why fog_density and these distances
## have to be tuned together. If you see things blinking into
## existence, either raise the fog or raise the distance.
func _fade(node: Node3D, dist: float) -> void:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).visibility_range_end = dist
		for c in n.get_children():
			stack.append(c)


func _register(pos: Vector3, kind: String, index: int, label: String, radius: float) -> void:
	interactables.append({
		"pos": Terrain.point(pos.x, pos.z),
		"kind": kind, "index": index, "label": label, "radius": radius,
	})


func _on_plot_changed(index: int) -> void:
	if index < _plot_views.size():
		_plot_views[index].refresh()


func _on_plots_rebuilt() -> void:
	for v in _plot_views:
		v.refresh()


## Nearest interactable to a world position, or {} if none in range.
func nearest_interactable(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for it in interactables + _placed_interactables:
		# A pickup that has been taken is not there to offer.
		if String(it["kind"]) == "gather" and GameState.is_gathered(int(it["index"])):
			continue
		var d: float = Vector2(from.x - it["pos"].x, from.z - it["pos"].z).length()
		if d <= float(it["radius"]) and d < best_d:
			best_d = d
			best = it
	return best
