# =============================================================
# props.gd — everything in the world, sculpted from ClayKit.
# -------------------------------------------------------------
# Each function returns a plain Node3D you can drop anywhere.
# There is not a single image file in this project — the whole
# look comes from the superellipsoid, the lathe, and the clay
# shader.
#
# SWAPPING IN REAL ART LATER:
# Replace the body of any one function with
#     var m := load("res://assets/models/house.glb").instantiate()
# and nothing else in the game changes. That's the whole point of
# keeping the sculpting in one file.
# =============================================================
class_name Props
extends RefCounted

# --- The builder lookup ---------------------------------------
# RECIPES rows name their sculptor as a string ("build": "lantern").
# This turns that string into the actual function, so world.gd and the
# build-mode ghost never need to know what craftables exist. Add a
# function below, name it in definitions.gd, and both the placed object
# and its preview work with no other edits.
#
# Every builder must run with NO arguments (give parameters defaults).
static var _instance: Props

static func build(fn: String) -> Node3D:
	if _instance == null:
		_instance = Props.new()          # static funcs need an instance to call()
	if fn == "" or not _instance.has_method(fn):
		push_warning("Props has no builder called '%s'" % fn)
		return null
	return _instance.call(fn) as Node3D


# --- Mushroom house ------------------------------------------
static func mushroom_house(cap_color: Color = Palette.DEEP_RED) -> Node3D:
	var root := Node3D.new()
	root.name = "MushroomHouse"

	# Stem: fat at the base, pinched at the waist, flaring to the cap.
	var stem_profile := PackedVector2Array([
		Vector2(1.30, 0.00), Vector2(1.22, 0.18), Vector2(1.02, 0.55),
		Vector2(0.94, 1.05), Vector2(1.00, 1.55), Vector2(1.12, 1.85),
		Vector2(0.98, 1.98),
	])
	root.add_child(ClayKit.lathe(stem_profile, Palette.CREAM, Vector3.ZERO,
		{"wobble": 0.035, "grain": 0.13, "noise_scale": 5.0}))

	# Cap
	var cap := ClayKit.dome(2.35, 1.5, cap_color, Vector3(0, 1.86, 0),
		{"wobble": 0.03, "grain": 0.09, "gloss": 0.4})
	root.add_child(cap)

	# Cream spots, following the curve of the cap rather than floating
	# near it. Nine of them: a bare-ish cap reads as a lampshade.
	cap_spots(root, 2.35, 1.5, 1.86, 9, 3, 1.0)

	# Arched door — Art Bible §4.1: "doors always arched, never rectangular"
	var door := ClayKit.blob(Vector3(0.95, 1.25, 0.55), Palette.EARTH_DARK,
		Vector3(0, 0.55, 0.86), {"wobble": 0.03, "grain": 0.15})
	root.add_child(door)
	root.add_child(ClayKit.blob(Vector3(0.16, 0.16, 0.16), Palette.WARM_YELLOW,
		Vector3(0.28, 0.60, 1.06), {"gloss": 0.5}))

	# Round window with a warm glow inside
	root.add_child(ClayKit.blob(Vector3(0.62, 0.62, 0.35), Palette.EARTH,
		Vector3(-0.72, 1.25, 0.62), {"wobble": 0.03}))
	root.add_child(ClayKit.blob(Vector3(0.44, 0.44, 0.30), Palette.WARM_YELLOW,
		Vector3(-0.75, 1.25, 0.72), {"emission": Palette.WARM_YELLOW, "emission_strength": 0.55}))

	# Moss and a couple of tiny mushrooms at the base (§4.1 accents)
	for p in ClayKit.ring_positions(5, 1.35, 0.06, 0.7):
		root.add_child(ClayKit.blob(Vector3(0.7, 0.18, 0.55), Palette.MOSS_DARK, p,
			{"wobble": 0.05, "grain": 0.2}))
	root.add_child(tiny_mushroom(Vector3(1.45, 0.0, 0.75), 0.85))
	root.add_child(tiny_mushroom(Vector3(-1.35, 0.0, -0.6), 0.6))
	return root


static func tiny_mushroom(pos: Vector3, scale_f: float, seed_n: int = 0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * scale_f
	n.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(0.10, 0.0), Vector2(0.07, 0.14), Vector2(0.09, 0.26)]),
		Palette.CREAM, Vector3.ZERO, {"segments": 10}))
	n.add_child(ClayKit.dome(0.22, 0.16, Palette.DEEP_RED, Vector3(0, 0.24, 0),
		{"segments": 12, "gloss": 0.4}))
	cap_spots(n, 0.22, 0.16, 0.24, 4, seed_n, 1.15)
	return n


# --- Spots ----------------------------------------------------
## Press pale spots onto a dome cap, hugging its curve.
##
## Every mushroom in Tendril Hills goes through here so they all
## read as the same species. `seed_n` shifts the pattern so no two
## mushrooms are stamped identically.
##
## Art Bible note: the "white" of this world is CREAM (#F5EFE0),
## never pure white. Pure white punches a hole in a warm palette.
static func cap_spots(parent: Node3D, radius: float, height: float, base_y: float,
		count: int, seed_n: int, spot_scale: float = 1.0,
		colour: Color = Palette.CREAM) -> void:
	for i in count:
		# Deterministic scatter — same mushroom, same spots, every run.
		var f := float(i) + float(seed_n) * 1.618
		var angle := fmod(f * 2.399963, TAU)              # golden angle
		var t := 0.22 + 0.62 * fmod(f * 0.7548, 1.0)      # 0 = rim, 1 = crown
		var r: float = radius * pow(cos(t * PI * 0.5), 0.65)
		var y: float = height * sin(t * PI * 0.5)
		var spot_r: float = radius * (0.13 + 0.09 * fmod(f * 0.4501, 1.0)) * spot_scale
		# Sunk slightly into the cap so it reads as pressed, not stuck on.
		var pos := Vector3(cos(angle) * r, base_y + y, sin(angle) * r) * 0.94
		pos.y = base_y + y * 0.94
		parent.add_child(ClayKit.blob(
			Vector3(spot_r * 2.0, spot_r * 1.5, spot_r * 2.0), colour, pos,
			{"segments": 8, "gloss": 0.3, "wobble": 0.03}))


# --- Trees (Forest Edge, World Design §2) --------------------
static func tree(height_scale: float = 1.0, tint: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	var h := 3.4 * height_scale
	root.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(0.62, 0.0), Vector2(0.44, h * 0.22), Vector2(0.34, h * 0.55),
		Vector2(0.30, h * 0.8), Vector2(0.24, h)]),
		Palette.EARTH_DARK, Vector3.ZERO, {"wobble": 0.04, "grain": 0.16, "noise_scale": 4.0}))

	var leaf_col := Palette.MOSS.lerp(Palette.MOSS_DARK, tint)
	var puffs := [
		{"p": Vector3(0, h + 0.55, 0), "s": 2.5},
		{"p": Vector3(0.95, h + 0.15, 0.45), "s": 1.8},
		{"p": Vector3(-0.85, h + 0.25, -0.5), "s": 1.9},
		{"p": Vector3(0.25, h + 1.25, -0.65), "s": 1.5},
		{"p": Vector3(-0.45, h + 1.0, 0.75), "s": 1.4},
	]
	for puff in puffs:
		var s: float = float(puff["s"]) * height_scale
		root.add_child(ClayKit.blob(Vector3(s, s * 0.82, s), leaf_col, puff["p"],
			{"wobble": 0.05, "grain": 0.14, "noise_scale": 3.5, "segments": 12}))
	return root


# --- Root Portal (World Design §2, west) ---------------------
static func root_portal() -> Node3D:
	var root := Node3D.new()
	root.name = "RootPortal"
	var dormant := Palette.EARTH_DARK.lerp(Palette.STONE, 0.22)

	# Two braided root pillars leaning toward each other
	for side in [-1.0, 1.0]:
		var pillar := Node3D.new()
		pillar.position = Vector3(side * 1.9, 0, 0)
		pillar.rotation_degrees = Vector3(0, 0, -side * 7.0)
		for strand in 3:
			var offset: float = float(strand) * TAU / 3.0
			var chain := Node3D.new()
			for i in 16:
				var t := float(i) / 15.0
				var a := offset + t * 5.2                      # tighter braid
				var r: float = 0.46 - t * 0.16
				var thick: float = 0.72 - t * 0.28             # tapers as it climbs
				chain.add_child(ClayKit.blob(
					Vector3(thick, thick * 0.92, thick),
					dormant.lerp(Palette.EARTH_DARK, t * 0.55),
					Vector3(cos(a) * r, 0.15 + t * 3.95, sin(a) * r),
					{"wobble": 0.07, "grain": 0.24, "noise_scale": 5.0, "segments": 10}))
			pillar.add_child(chain)
		# Gnarled roots gripping the ground at the base.
		for i in 5:
			var a := TAU * float(i) / 5.0
			var root_arm := ClayKit.blob(Vector3(1.25, 0.42, 0.44),
				dormant.darkened(0.1), Vector3(cos(a) * 0.62, 0.12, sin(a) * 0.62),
				{"wobble": 0.08, "grain": 0.26, "segments": 10})
			root_arm.rotation_degrees = Vector3(0, -rad_to_deg(a), 9.0)
			pillar.add_child(root_arm)
		root.add_child(pillar)

	# The arch itself — two strands braiding over the gap.
	var arch := Node3D.new()
	arch.name = "Arch"
	for strand in 2:
		for i in 20:
			var t := float(i) / 19.0
			var ang: float = PI * t
			var weave: float = sin(t * PI * 3.0 + float(strand) * PI) * 0.20
			var thick: float = 0.52 + 0.14 * sin(t * PI)
			arch.add_child(ClayKit.blob(Vector3(thick, thick, thick),
				dormant.lerp(Palette.EARTH_DARK, 0.3 + 0.3 * sin(t * PI)),
				Vector3(-cos(ang) * (2.05 + weave * 0.4), 4.02 + sin(ang) * 1.35,
					weave + (0.14 if strand == 0 else -0.14)),
				{"wobble": 0.07, "grain": 0.24, "noise_scale": 5.0, "segments": 10}))
	root.add_child(arch)

	# The veil — invisible while dormant, glowing once unlocked
	var veil := ClayKit.blob(Vector3(3.5, 4.4, 0.3), Palette.SKY_BLUE, Vector3(0, 2.3, 0),
		{"alpha": 0.0, "emission": Palette.SKY_BLUE, "emission_strength": 0.0, "segments": 16})
	veil.name = "Veil"
	root.add_child(veil)

	# Small sign: "Something stirs beyond..."
	root.add_child(sign_post(Vector3(2.9, 0, 1.6), -25.0))
	return root


static func sign_post(pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw, 0)
	n.add_child(ClayKit.stalk(Vector3(0.18, 1.15, 0.18), Palette.EARTH_DARK, Vector3(0, 0.55, 0)))
	var board := Node3D.new()
	board.position = Vector3(0, 1.18, 0)
	board.rotation_degrees = Vector3(-9, 0, 2)
	board.add_child(ClayKit.slab(Vector3(1.30, 0.74, 0.14), Palette.EARTH_DARK, Vector3.ZERO,
		{"wobble": 0.03}))
	board.add_child(ClayKit.slab(Vector3(1.08, 0.54, 0.16), Palette.CREAM, Vector3(0, 0.01, 0.02),
		{"wobble": 0.04, "grain": 0.16}))
	# Three pressed lines standing in for carved lettering.
	for i in 3:
		board.add_child(ClayKit.blob(Vector3(0.62 - 0.14 * float(i), 0.05, 0.06),
			Palette.EARTH_DARK, Vector3(-0.06 + 0.03 * float(i), 0.13 - 0.13 * float(i), 0.10),
			{"segments": 6}))
	n.add_child(board)
	return n


# --- Village fittings ----------------------------------------
static func market_stall() -> Node3D:
	var root := Node3D.new()
	root.name = "MarketStall"
	for x in [-1.5, 1.5]:
		for z in [-0.7, 0.7]:
			root.add_child(ClayKit.stalk(Vector3(0.18, 1.9, 0.18), Palette.EARTH,
				Vector3(x, 0.95, z)))
	root.add_child(ClayKit.slab(Vector3(3.6, 0.16, 1.1), Palette.EARTH_DARK, Vector3(0, 1.05, 0)))
	# Striped awning made of alternating rounded slats
	for i in 7:
		var col: Color = Palette.DEEP_RED if i % 2 == 0 else Palette.CREAM
		root.add_child(ClayKit.slab(Vector3(0.52, 0.14, 2.0), col,
			Vector3(-1.56 + i * 0.52, 2.05, 0), {"gloss": 0.15}))
	# Seed packets on the counter
	for i in 4:
		root.add_child(ClayKit.slab(Vector3(0.3, 0.38, 0.06), Palette.CLAY_TAN,
			Vector3(-1.0 + i * 0.66, 1.3, 0.2), {"wobble": 0.02}))
	# A basket of produce
	root.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(0.28, 0.0), Vector2(0.36, 0.28)]), Palette.EARTH, Vector3(1.2, 1.13, -0.1)))
	root.add_child(ClayKit.blob(Vector3(0.22, 0.22, 0.22), Palette.CARROT, Vector3(1.14, 1.44, -0.14)))
	root.add_child(ClayKit.blob(Vector3(0.2, 0.2, 0.2), Palette.DEEP_RED, Vector3(1.3, 1.42, -0.02)))
	return root


static func quest_board() -> Node3D:
	var root := Node3D.new()
	root.name = "QuestBoard"
	for x in [-0.85, 0.85]:
		root.add_child(ClayKit.stalk(Vector3(0.2, 2.0, 0.2), Palette.EARTH, Vector3(x, 1.0, 0)))
	root.add_child(ClayKit.slab(Vector3(2.3, 1.5, 0.16), Palette.EARTH_DARK, Vector3(0, 1.75, 0)))
	for i in 3:
		root.add_child(ClayKit.slab(Vector3(0.55, 0.7, 0.05), Palette.CREAM,
			Vector3(-0.62 + i * 0.62, 1.72 + (0.06 if i == 1 else 0.0), 0.11),
			{"wobble": 0.04}))
	root.add_child(ClayKit.dome(0.5, 0.3, Palette.WARM_YELLOW, Vector3(0, 2.5, 0), {"gloss": 0.4}))
	return root


## The big decorative mushroom at the village centre.
static func landmark_mushroom() -> Node3D:
	var root := Node3D.new()
	root.name = "Landmark"
	root.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(1.0, 0.0), Vector2(0.78, 0.9), Vector2(0.68, 2.2),
		Vector2(0.80, 3.1), Vector2(0.70, 3.3)]),
		Palette.CREAM, Vector3.ZERO, {"wobble": 0.035, "grain": 0.12}))
	root.add_child(ClayKit.dome(2.9, 1.9, Palette.CARROT, Vector3(0, 3.2, 0), {"gloss": 0.42}))
	cap_spots(root, 2.9, 1.9, 3.2, 11, 7, 0.95)
	for p in ClayKit.ring_positions(7, 1.25, 0.05, 0.2):
		root.add_child(ClayKit.blob(Vector3(0.75, 0.2, 0.6), Palette.MOSS_DARK, p, {"grain": 0.2}))
	return root


static func fence_post(height_f: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.add_child(ClayKit.stalk(Vector3(0.2, 0.95 * height_f, 0.2), Palette.EARTH,
		Vector3(0, 0.48 * height_f, 0)))
	n.add_child(ClayKit.dome(0.16, 0.12, Palette.EARTH_DARK, Vector3(0, 0.95 * height_f, 0),
		{"segments": 8}))
	return n


static func rock(size: float, tint: Color = Palette.STONE) -> Node3D:
	var n := Node3D.new()
	n.add_child(ClayKit.blob(Vector3(size, size * 0.72, size * 0.86), tint, Vector3(0, size * 0.28, 0),
		{"wobble": 0.06, "grain": 0.22, "noise_scale": 5.0, "segments": 10}))
	return n


static func flower_cluster(col: Color) -> Node3D:
	var n := Node3D.new()
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.6
		var base := Vector3(cos(a) * 0.16, 0, sin(a) * 0.16)
		n.add_child(ClayKit.stalk(Vector3(0.05, 0.34, 0.05), Palette.LEAF, base + Vector3(0, 0.17, 0),
			{"segments": 8}))
		n.add_child(ClayKit.blob(Vector3(0.2, 0.1, 0.2), col, base + Vector3(0, 0.36, 0),
			{"segments": 8, "gloss": 0.25}))
		n.add_child(ClayKit.blob(Vector3(0.08, 0.08, 0.08), Palette.WARM_YELLOW,
			base + Vector3(0, 0.4, 0), {"segments": 6}))
	return n


# --- Crops ----------------------------------------------------
## stage: 0 sprout, 1 growing, 2 ready to harvest
static func crop(crop_id: String, stage: int) -> Node3D:
	var d: Dictionary = Defs.CROPS[crop_id]
	var col: Color = d["color"]
	var leaf_col: Color = d["leaf"]
	var n := Node3D.new()
	n.name = "Crop"

	# Art Bible §4.2: "chunky, oversized relative to real life."
	# These are deliberately bigger than a real vegetable — at this
	# camera distance anything life-sized disappears into the soil.
	if stage == 0:
		n.add_child(ClayKit.stalk(Vector3(0.10, 0.30, 0.10), leaf_col, Vector3(0, 0.15, 0),
			{"segments": 8}))
		n.add_child(ClayKit.leaf(0.34, leaf_col, 42.0, 25.0))
		n.add_child(ClayKit.leaf(0.30, leaf_col, 42.0, 205.0))
		return n

	var full := stage == 2
	var leaf_len: float = 0.62 if not full else 1.0
	var leaves: int = 4 if not full else 6
	for i in leaves:
		n.add_child(ClayKit.leaf(leaf_len * (0.78 + 0.22 * float(i % 2)), leaf_col,
			34.0 + 9.0 * float(i % 3), 360.0 * float(i) / float(leaves) + 15.0))

	if full:
		# "Roots slightly visible above soil when fully grown."
		match crop_id:
			"carrot":
				n.add_child(ClayKit.lathe(PackedVector2Array([
					Vector2(0.03, -0.70), Vector2(0.20, -0.44), Vector2(0.30, -0.10),
					Vector2(0.34, 0.20), Vector2(0.30, 0.40), Vector2(0.20, 0.50)]),
					col, Vector3(0, 0.18, 0), {"grain": 0.18, "noise_scale": 12.0}))
				# Shoulder ridges — reads unmistakably as a carrot top.
				for i in 3:
					var a := TAU * float(i) / 3.0
					n.add_child(ClayKit.blob(Vector3(0.12, 0.30, 0.12), col.darkened(0.08),
						Vector3(cos(a) * 0.28, 0.42, sin(a) * 0.28), {"segments": 8}))
			"radish":
				n.add_child(ClayKit.blob(Vector3(0.70, 0.74, 0.70), col, Vector3(0, 0.34, 0),
					{"gloss": 0.28, "grain": 0.12}))
				n.add_child(ClayKit.lathe(PackedVector2Array([
					Vector2(0.02, -0.35), Vector2(0.16, -0.12), Vector2(0.24, 0.06)]),
					Palette.CREAM, Vector3(0, 0.06, 0), {"segments": 12}))
			_:
				n.add_child(ClayKit.blob(Vector3(0.76, 0.62, 0.76), col, Vector3(0, 0.30, 0),
					{"gloss": 0.22, "grain": 0.12}))
				n.add_child(ClayKit.blob(Vector3(0.50, 0.34, 0.50), Palette.CREAM,
					Vector3(0, 0.05, 0), {"segments": 10}))
	else:
		n.add_child(ClayKit.blob(Vector3(0.28, 0.22, 0.28), col, Vector3(0, 0.12, 0),
			{"segments": 10}))
	return n


# --- Gatherables and craftables ------------------------------
## A fallen branch. Gives the forest edge a reason to walk into it.
static func branch(seed_n: int = 0) -> Node3D:
	var n := Node3D.new()
	n.name = "Branch"
	var len_f := 0.85 + 0.35 * fmod(float(seed_n) * 0.618, 1.0)
	var main := ClayKit.stalk(Vector3(0.13, len_f, 0.13), Palette.EARTH_DARK,
		Vector3(0, 0.09, 0), {"segments": 8, "grain": 0.24, "wobble": 0.05})
	main.rotation_degrees = Vector3(90, 0, 0)      # lying down
	n.add_child(main)
	# A couple of side twigs so it is not just a dowel.
	for i in 2:
		var t := ClayKit.stalk(Vector3(0.07, 0.3, 0.07), Palette.EARTH_DARK,
			Vector3(0, 0.09, -0.15 + 0.35 * float(i)), {"segments": 6, "grain": 0.26})
		t.rotation_degrees = Vector3(70, 35.0 - 70.0 * float(i), 20)
		n.add_child(t)
	var leaf_i := ClayKit.leaf(0.26, Palette.MOSS_DARK, 12.0, 40.0 + 120.0 * float(seed_n % 3))
	leaf_i.position = Vector3(0, 0.12, 0.25)
	n.add_child(leaf_i)
	return n


## Clay lantern — a crafted light. Reads best at the golden hour the
## whole world is lit for.
static func lantern() -> Node3D:
	var n := Node3D.new()
	n.name = "Lantern"
	n.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(0.30, 0.0), Vector2(0.22, 0.16), Vector2(0.16, 0.5)]),
		Palette.STONE, Vector3.ZERO, {"grain": 0.2}))
	n.add_child(ClayKit.stalk(Vector3(0.13, 0.7, 0.13), Palette.EARTH_DARK,
		Vector3(0, 0.85, 0), {"segments": 8}))
	# The glass: a warm blob that actually emits.
	n.add_child(ClayKit.blob(Vector3(0.46, 0.54, 0.46), Palette.WARM_YELLOW,
		Vector3(0, 1.32, 0), {"emission": Palette.WARM_YELLOW,
		"emission_strength": 1.6, "gloss": 0.5, "segments": 12}))
	n.add_child(ClayKit.dome(0.34, 0.22, Palette.DEEP_RED, Vector3(0, 1.56, 0),
		{"segments": 12, "gloss": 0.4}))
	# Two lights: a bright small one for the glass, and a wide soft one
	# that actually pools on the grass. One light doing both jobs either
	# blows out the lantern or fails to light anything around it.
	var core := OmniLight3D.new()
	core.light_color = Palette.WARM_YELLOW
	core.light_energy = 1.6
	core.omni_range = 2.4
	core.position = Vector3(0, 1.32, 0)
	core.shadow_enabled = false
	n.add_child(core)

	var pool := OmniLight3D.new()
	pool.light_color = Palette.WARM_YELLOW.lerp(Palette.CARROT, 0.25)
	pool.light_energy = 1.1
	pool.omni_range = 9.0
	pool.omni_attenuation = 1.6
	pool.position = Vector3(0, 0.9, 0)
	pool.shadow_enabled = false
	n.add_child(pool)
	return n


## A single worn stepping stone, flush with the ground.
static func path_stone(seed_n: int = 0) -> Node3D:
	var n := Node3D.new()
	n.name = "PathStone"
	var w := 0.75 + 0.3 * fmod(float(seed_n) * 0.618, 1.0)
	n.add_child(ClayKit.blob(Vector3(w, 0.2, w * 0.82),
		Palette.CLAY_TAN.darkened(0.05), Vector3(0, 0.03, 0),
		{"segments": 10, "grain": 0.22}))
	return n


## Flower planter — a pot of clay blooms. Cheap on purpose: this is
## the one kids will place forty of, and that is a fine thing to do.
static func planter(seed_n: int = 0) -> Node3D:
	var n := Node3D.new()
	n.name = "Planter"
	n.add_child(ClayKit.lathe(PackedVector2Array([
		Vector2(0.30, 0.0), Vector2(0.36, 0.36), Vector2(0.40, 0.46),
		Vector2(0.34, 0.50)]), Palette.CLAY_TAN, Vector3.ZERO,
		{"grain": 0.18, "wobble": 0.03}))
	n.add_child(ClayKit.blob(Vector3(0.64, 0.14, 0.64), Palette.SOIL_WET,
		Vector3(0, 0.48, 0), {"segments": 12, "grain": 0.24}))
	var blooms := [Palette.WARM_YELLOW, Palette.DEEP_RED, Palette.SOFT_PURPLE,
		Palette.SKY_BLUE, Palette.CREAM]
	for i in 5:
		var a := TAU * float(i) / 5.0 + float(seed_n)
		var base := Vector3(cos(a) * 0.17, 0.5, sin(a) * 0.17)
		n.add_child(ClayKit.stalk(Vector3(0.06, 0.34, 0.06), Palette.LEAF,
			base + Vector3(0, 0.17, 0), {"segments": 8}))
		var col: Color = blooms[(i + seed_n) % blooms.size()]
		n.add_child(ClayKit.blob(Vector3(0.24, 0.12, 0.24), col,
			base + Vector3(0, 0.36, 0), {"segments": 10, "gloss": 0.25}))
		n.add_child(ClayKit.blob(Vector3(0.09, 0.09, 0.09), Palette.WARM_YELLOW,
			base + Vector3(0, 0.40, 0), {"segments": 6}))
	return n


## A signpost the player puts up themselves. Same shape as the ones
## already in the world, so a player-placed sign belongs.
## A signpost with a name actually painted on it.
##
## sign_post() has three pressed clay lines standing in for lettering
## you are not meant to read. Once there is a real word on the board
## those lines only fight it, so this is a separate sculpt rather than
## a flag on that one. Used for the homesteads — see World.HOMESTEADS.
static func named_sign(text: String, tint: Color = Palette.CREAM) -> Node3D:
	var n := Node3D.new()
	n.name = "NamedSign"
	n.add_child(ClayKit.stalk(Vector3(0.18, 1.20, 0.18), Palette.EARTH_DARK,
		Vector3(0, 0.58, 0)))

	var board := Node3D.new()
	board.position = Vector3(0, 1.24, 0)
	board.rotation_degrees = Vector3(-9, 0, 2)
	board.add_child(ClayKit.slab(Vector3(1.86, 0.64, 0.14), Palette.EARTH_DARK,
		Vector3.ZERO, {"wobble": 0.03}))
	board.add_child(ClayKit.slab(Vector3(1.62, 0.46, 0.16), tint,
		Vector3(0, 0.01, 0.0), {"wobble": 0.04, "grain": 0.16}))

	# Shrink the lettering to fit the board rather than letting a long
	# name run off both ends. Rough but reliable: a glyph averages a
	# bit over half the font size wide. Rename a homestead to
	# something enormous and it gets smaller, not broken.
	const BOARD_TEXT_WIDTH := 1.44
	var font_px := 128.0
	var est_width: float = maxf(1.0, float(text.length())) * 0.55 * font_px
	var px_size: float = minf(0.0030, BOARD_TEXT_WIDTH / est_width)

	# Painted on BOTH faces, on purpose. A sign has a front, and
	# whoever places it has to decide which way the front points --
	# and then every player who walks up from the other side reads
	# a blank brown board. Two labels cost one draw call and remove
	# the whole question.
	#
	# Label3D draws on a quad facing local +Z, same as Sprite3D, so
	# each one sits just proud of its face or it z-fights the board.
	for face in [1.0, -1.0]:
		var label := Label3D.new()
		label.name = "Name+" if face > 0.0 else "Name-"
		label.text = text
		label.font_size = int(font_px)
		label.pixel_size = px_size
		label.modulate = Palette.UI_TEXT
		label.outline_size = 0
		label.position = Vector3(0, 0.01, 0.10 * face)
		label.rotation_degrees.y = 0.0 if face > 0.0 else 180.0
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.shaded = false
		label.double_sided = false
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		board.add_child(label)

	n.add_child(board)
	return n


static func player_sign() -> Node3D:
	var n := sign_post(Vector3.ZERO, 0.0)
	n.name = "PlayerSign"
	return n


## Scarecrow. Crops within SCARECROW_RADIUS grow faster — the first
## placeable that pays you back in something other than looks.
static func scarecrow() -> Node3D:
	var n := Node3D.new()
	n.name = "Scarecrow"
	# Post and crossbar
	n.add_child(ClayKit.stalk(Vector3(0.16, 2.0, 0.16), Palette.EARTH_DARK,
		Vector3(0, 1.0, 0), {"grain": 0.2}))
	var bar := ClayKit.stalk(Vector3(0.13, 1.5, 0.13), Palette.EARTH_DARK,
		Vector3(0, 1.42, 0), {"grain": 0.2})
	bar.rotation_degrees = Vector3(0, 0, 90)
	n.add_child(bar)
	# Straw body in a tunic
	n.add_child(ClayKit.blob(Vector3(0.72, 0.86, 0.5), Palette.MOSS_DARK,
		Vector3(0, 1.28, 0), {"wobble": 0.05, "grain": 0.16}))
	for i in 7:
		var a := TAU * float(i) / 7.0
		var straw := ClayKit.blob(Vector3(0.1, 0.34, 0.1), Palette.WARM_YELLOW,
			Vector3(cos(a) * 0.28, 0.92, sin(a) * 0.2), {"segments": 6, "grain": 0.3})
		straw.rotation_degrees = Vector3(18, 0, 20.0 - 40.0 * fmod(float(i) * 0.37, 1.0))
		n.add_child(straw)
	# Sack head with stitched eyes and a crooked grin
	n.add_child(ClayKit.blob(Vector3(0.62, 0.68, 0.58), Palette.CREAM,
		Vector3(0, 1.95, 0), {"wobble": 0.04, "grain": 0.15}))
	for sx in [-0.15, 0.15]:
		n.add_child(ClayKit.blob(Vector3(0.11, 0.13, 0.08), Palette.EARTH_DARK,
			Vector3(sx, 2.0, -0.27), {"segments": 8}))
	for i in 4:
		var t := (float(i) / 3.0 - 0.5) * 2.0
		n.add_child(ClayKit.blob(Vector3(0.06, 0.05, 0.05), Palette.EARTH_DARK,
			Vector3(t * 0.13, 1.83 - 0.03 * (1.0 - absf(t)), -0.26), {"segments": 6}))
	# Straw hair and a floppy hat
	n.add_child(ClayKit.dome(0.5, 0.24, Palette.CARROT, Vector3(0, 2.24, 0),
		{"segments": 14, "gloss": 0.15}))
	n.add_child(ClayKit.blob(Vector3(1.05, 0.1, 1.05), Palette.CARROT.darkened(0.08),
		Vector3(0, 2.24, 0), {"segments": 14, "wobble": 0.05}))
	# A perched friend, because a scarecrow that scares nothing is funnier
	n.add_child(ClayKit.blob(Vector3(0.22, 0.2, 0.28), Palette.EARTH_DARK,
		Vector3(0.62, 1.55, 0), {"segments": 10}))
	n.add_child(ClayKit.blob(Vector3(0.1, 0.09, 0.1), Palette.EARTH_DARK,
		Vector3(0.62, 1.68, -0.09), {"segments": 8}))
	n.add_child(ClayKit.blob(Vector3(0.07, 0.05, 0.09), Palette.WARM_YELLOW,
		Vector3(0.62, 1.68, -0.19), {"segments": 6}))
	return n


## Bee hive. Fills with honey on a timer; walk up and press E.
## `full` swaps in the ready-to-collect look.
static func hive(full: bool = false) -> Node3D:
	var n := Node3D.new()
	n.name = "Hive"
	n.add_child(ClayKit.stalk(Vector3(0.5, 0.16, 0.5), Palette.EARTH_DARK,
		Vector3(0, 0.08, 0), {"segments": 12}))
	# Stacked skep rings, fattest in the middle
	var rings := 4
	for i in rings:
		var t := float(i) / float(rings - 1)
		var w: float = 0.86 - 0.30 * absf(t - 0.35) * 1.6
		n.add_child(ClayKit.lathe(PackedVector2Array([
			Vector2(w * 0.5, 0.0), Vector2(w * 0.53, 0.1), Vector2(w * 0.5, 0.2)]),
			Palette.WARM_YELLOW.darkened(0.12 - 0.03 * float(i)),
			Vector3(0, 0.16 + 0.2 * float(i), 0),
			{"segments": 14, "grain": 0.22, "wobble": 0.035}))
	n.add_child(ClayKit.dome(0.32, 0.22, Palette.WARM_YELLOW.darkened(0.05),
		Vector3(0, 0.96, 0), {"segments": 12, "gloss": 0.25}))
	# Entrance hole
	n.add_child(ClayKit.blob(Vector3(0.22, 0.14, 0.12), Palette.EARTH_DARK,
		Vector3(0, 0.34, -0.42), {"segments": 8}))
	if full:
		# Honey beading at the lip, and a couple of bees doing rounds.
		n.add_child(ClayKit.blob(Vector3(0.26, 0.18, 0.16), Palette.WARM_YELLOW,
			Vector3(0, 0.24, -0.44), {"segments": 8, "gloss": 0.85,
			"emission": Palette.WARM_YELLOW, "emission_strength": 0.5}))
		for i in 3:
			var a := TAU * float(i) / 3.0
			n.add_child(ClayKit.blob(Vector3(0.1, 0.09, 0.13), Palette.WARM_YELLOW,
				Vector3(cos(a) * 0.7, 0.8 + 0.15 * float(i), sin(a) * 0.7),
				{"segments": 6, "emission": Palette.WARM_YELLOW,
				"emission_strength": 0.7}))
	return n


## The workbench. Where gathered material becomes something you can
## put down.
static func workbench() -> Node3D:
	var n := Node3D.new()
	n.name = "Workbench"
	for x in [-0.8, 0.8]:
		for z in [-0.42, 0.42]:
			n.add_child(ClayKit.stalk(Vector3(0.18, 0.85, 0.18), Palette.EARTH_DARK,
				Vector3(x, 0.42, z)))
	n.add_child(ClayKit.slab(Vector3(2.1, 0.2, 1.15), Palette.EARTH, Vector3(0, 0.92, 0),
		{"grain": 0.18}))
	# Tools and offcuts on the top, so it reads as in use.
	n.add_child(ClayKit.blob(Vector3(0.5, 0.16, 0.34), Palette.STONE,
		Vector3(-0.55, 1.05, 0.1), {"segments": 10, "grain": 0.22}))
	var mallet := ClayKit.stalk(Vector3(0.1, 0.5, 0.1), Palette.EARTH_DARK,
		Vector3(0.45, 1.06, -0.1), {"segments": 8})
	mallet.rotation_degrees = Vector3(0, 0, 78)
	n.add_child(mallet)
	n.add_child(ClayKit.slab(Vector3(0.3, 0.26, 0.26), Palette.CLAY_TAN,
		Vector3(0.72, 1.14, -0.1), {"grain": 0.2}))
	n.add_child(branch(1))
	n.get_child(n.get_child_count() - 1).position = Vector3(0.05, 1.02, 0.3)
	# A little pile of gathered bits underneath
	n.add_child(ClayKit.blob(Vector3(0.4, 0.24, 0.36), Palette.STONE,
		Vector3(-1.15, 0.12, 0.3), {"segments": 10, "grain": 0.24}))
	n.add_child(tiny_mushroom(Vector3(1.2, 0.0, 0.45), 1.1, 5))
	return n


# --- Characters ----------------------------------------------
## The Sprite. Art Bible §2: head:body = 1:1.2, top-heavy, mitten
## hands, big eyes. Returns a rig whose parts are named so the
## player script can bob and waddle them.
##
## THE FACE POINTS -Z. That is Godot's forward: look_at() assumes it,
## -basis.z is what build mode aims along, and imported .glb models
## are authored that way. Sculpt any new facial feature at negative
## Z or the Sprite walks backwards.
static func sprite_body(skin: Color = Palette.CLAY_TAN, tunic: Color = Palette.MOSS,
		is_elder: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# Torso — soft, rounded, no angles
	body.add_child(ClayKit.blob(Vector3(0.78, 0.86, 0.72), tunic, Vector3(0, 0.52, 0),
		{"wobble": 0.03, "grain": 0.12}))
	# Layered leaf collar
	for i in 5:
		var a := TAU * float(i) / 5.0
		body.add_child(ClayKit.blob(Vector3(0.34, 0.1, 0.26),
			tunic.lightened(0.12),
			Vector3(cos(a) * 0.34, 0.80, sin(a) * 0.30),
			{"segments": 10, "wobble": 0.05}))

	# Head
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.16, 0)
	body.add_child(head)
	head.add_child(ClayKit.blob(Vector3(0.92, 0.98, 0.88), skin, Vector3.ZERO,
		{"wobble": 0.025, "grain": 0.10}))
	# Eyes — 30% of face height per the Art Bible
	for sx in [-0.22, 0.22]:
		head.add_child(ClayKit.blob(Vector3(0.26, 0.30, 0.20), Palette.CREAM,
			Vector3(sx, 0.04, -0.38), {"segments": 10, "wobble": 0.01}))
		head.add_child(ClayKit.blob(Vector3(0.15, 0.18, 0.14), Palette.EYE_DARK,
			Vector3(sx * 1.05, 0.02, -0.46), {"segments": 10, "wobble": 0.0}))
		head.add_child(ClayKit.blob(Vector3(0.055, 0.055, 0.05), Palette.CREAM,
			Vector3(sx * 1.05 + 0.045, 0.08, -0.50), {"segments": 6, "wobble": 0.0}))
	# Rosy cheeks
	for sx in [-0.34, 0.34]:
		head.add_child(ClayKit.blob(Vector3(0.24, 0.16, 0.14), Palette.ROSY,
			Vector3(sx, -0.16, -0.30), {"segments": 8, "wobble": 0.02}))
	# Small rounded nose + gentle smile
	head.add_child(ClayKit.blob(Vector3(0.14, 0.12, 0.14), skin.darkened(0.08),
		Vector3(0, -0.08, -0.44), {"segments": 8}))
	for i in 5:
		var t := (float(i) / 4.0 - 0.5) * 2.0
		head.add_child(ClayKit.blob(Vector3(0.07, 0.05, 0.05), Palette.EARTH_DARK,
			Vector3(t * 0.15, -0.26 - 0.03 * (1.0 - absf(t)), -0.42),
			{"segments": 6, "wobble": 0.0}))
	# Small pointed ears
	for sx in [-1.0, 1.0]:
		head.add_child(ClayKit.blob(Vector3(0.14, 0.28, 0.12), skin,
			Vector3(sx * 0.46, 0.06, 0.0), {"segments": 8}))

	# Vine headpiece (default look) or elder's mossy hat
	if is_elder:
		head.add_child(ClayKit.dome(0.72, 0.55, Palette.MOSS_DARK, Vector3(0, 0.34, 0), {"gloss": 0.2}))
		head.add_child(ClayKit.blob(Vector3(0.5, 0.46, 0.3), Palette.CREAM,
			Vector3(0, -0.42, -0.30), {"wobble": 0.06, "grain": 0.22}))  # beard
	else:
		for i in 6:
			var a := TAU * float(i) / 6.0
			head.add_child(ClayKit.blob(Vector3(0.16, 0.1, 0.13), Palette.LEAF,
				Vector3(cos(a) * 0.42, 0.40, sin(a) * 0.38), {"segments": 8}))

	# Arms — stubby, mitten hands
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(side * 0.42, 0.66, 0)
		body.add_child(arm)
		arm.add_child(ClayKit.blob(Vector3(0.24, 0.46, 0.24), tunic.lightened(0.05),
			Vector3(0, -0.16, 0), {"segments": 10}))
		arm.add_child(ClayKit.blob(Vector3(0.26, 0.24, 0.24), skin,
			Vector3(0, -0.40, -0.02), {"segments": 10}))

	# Legs — short, rounded feet
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(side * 0.21, 0.20, 0)
		body.add_child(leg)
		leg.add_child(ClayKit.blob(Vector3(0.26, 0.28, 0.26), skin.darkened(0.05),
			Vector3(0, -0.04, 0), {"segments": 10}))
		leg.add_child(ClayKit.blob(Vector3(0.28, 0.18, 0.4), Palette.EARTH,
			Vector3(0, -0.16, -0.06), {"segments": 10}))

	return root


static func old_sprout() -> Node3D:
	var n := Node3D.new()
	n.name = "OldSprout"
	var rig := sprite_body(Palette.CLAY_TAN.darkened(0.12), Palette.MOSS_DARK, true)
	rig.scale = Vector3.ONE * 1.12
	n.add_child(rig)
	# Walking staff
	var staff := ClayKit.lathe(PackedVector2Array([
		Vector2(0.07, 0.0), Vector2(0.05, 1.3), Vector2(0.09, 1.7)]),
		Palette.EARTH, Vector3(0.62, 0.0, 0.14), {"segments": 10})
	staff.rotation_degrees = Vector3(4, 0, -6)
	n.add_child(staff)
	n.add_child(ClayKit.blob(Vector3(0.26, 0.26, 0.26), Palette.WARM_YELLOW,
		Vector3(0.68, 1.78, 0.14),
		{"emission": Palette.WARM_YELLOW, "emission_strength": 0.6, "segments": 10}))
	return n
