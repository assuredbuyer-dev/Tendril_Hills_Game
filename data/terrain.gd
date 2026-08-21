# =============================================================
# terrain.gd — one source of truth for "how high is the ground?"
# -------------------------------------------------------------
# Both the terrain mesh AND everything standing on it (plots,
# houses, trees, the player's spawn) ask this same function, so
# nothing ever floats or sinks. Change the landscape here and the
# whole world moves with it.
#
# Layout follows World Design §2:
#   village centre  = middle (flat, buildable, SHARED)
#   farm zone       = east   (flat, tillable, SHARED)
#   root portal     = west
#   spawn           = south
#   homesteads      = four clearings on the diagonals, one per
#                     player, each with its own soil (see HOMESTEADS)
#   forest edge     = north + the outer ring (decorative border)
# =============================================================
class_name Terrain
extends RefCounted

const HALF_SIZE := 68.0          # world spans -68..68 on X and Z
const ROLL_HEIGHT := 1.55        # how tall the gentle hills are
const RIM_BAND := 15.0           # how wide the bowl rim is, in metres

const VILLAGE_CENTRE := Vector3(0, 0, 0)
const VILLAGE_RADIUS := 11.0
const FARM_CENTRE := Vector3(17.0, 0, 1.0)
const FARM_HALF := Vector2(7.0, 6.0)
const PORTAL_POS := Vector3(-19.0, 0, -2.0)
const SPAWN_POS := Vector3(0, 0, 12.0)

# -------------------------------------------------------------
#  Homesteads — one clearing per player
# -------------------------------------------------------------
# The village in the middle stays shared: Old Sprout, the stall,
# the workbench, the quest board and the portal belong to
# everyone. These four clearings do not. Each is flat, buildable,
# and has its own patch of soil, so every player has somewhere
# that is theirs.
#
# This is ONE list and everything reads from it — the terrain
# flattening, the signposts, the soil grid, and the spawn points
# when this becomes multiplayer. Add a fifth entry and a fifth
# homestead appears, fully working, with no other edit.
#
# `pos` is the centre of the clearing (where the signpost goes).
# `farm` is where that homestead's soil grid is centred.
# Rename them. They are your hills.
const HOMESTEAD_RADIUS := 11.0
const HOMESTEADS := [
	{"name": "Bramblewick", "pos": Vector3(-32.0, 0, -32.0), "farm": Vector3(-35.5, 0, -28.5)},
	{"name": "Honeyhollow", "pos": Vector3(32.0, 0, -32.0),  "farm": Vector3(35.5, 0, -28.5)},
	{"name": "Thistledown", "pos": Vector3(32.0, 0, 32.0),   "farm": Vector3(35.5, 0, 28.5)},
	{"name": "Mosswood",    "pos": Vector3(-32.0, 0, 32.0),  "farm": Vector3(-35.5, 0, 28.5)},
]
# Each homestead's soil is a small square; the shared farm to the
# east stays the big one, because that is where you learn.
const HOMESTEAD_FARM_HALF := Vector2(3.0, 3.0)

static var _noise: FastNoiseLite


static func _get_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 20260817
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.022
		_noise.fractal_octaves = 3
		_noise.fractal_gain = 0.42
	return _noise


## Ground height at any point in the world.
static func height(x: float, z: float) -> float:
	var n := _get_noise().get_noise_2d(x, z)          # -1..1
	var h: float = n * ROLL_HEIGHT

	# The outer ring rises into a soft bowl rim so the world reads
	# as a diorama on a shelf rather than a plane that stops.
	var d := Vector2(x, z).length()
	var rim := smoothstep(HALF_SIZE - RIM_BAND, HALF_SIZE, d)
	h += rim * 5.5

	# Flatten the two zones the player builds on.
	h = lerp(h, 0.0, _flatten_circle(x, z, VILLAGE_CENTRE, VILLAGE_RADIUS, 5.0))
	h = lerp(h, 0.0, _flatten_rect(x, z, FARM_CENTRE, FARM_HALF, 3.5))
	# A level apron in front of the portal so the archway sits true.
	h = lerp(h, 0.35, _flatten_circle(x, z, PORTAL_POS, 4.0, 3.0))
	# Every homestead gets the same treatment as the village: flat
	# enough to build on, feathered so it still sits in the hills
	# rather than looking stamped out of them.
	for hs in HOMESTEADS:
		h = lerp(h, 0.0, _flatten_circle(x, z, hs["pos"], HOMESTEAD_RADIUS, 6.0))
	return h


## Surface point + normal, for placing objects flush to the ground.
static func point(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


static func normal(x: float, z: float) -> Vector3:
	var e := 0.35
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


static func _flatten_circle(x: float, z: float, centre: Vector3, radius: float, feather: float) -> float:
	var d := Vector2(x - centre.x, z - centre.z).length()
	return 1.0 - smoothstep(radius, radius + feather, d)


static func _flatten_rect(x: float, z: float, centre: Vector3, half: Vector2, feather: float) -> float:
	var dx: float = absf(x - centre.x) - half.x
	var dz: float = absf(z - centre.z) - half.y
	var d: float = maxf(maxf(dx, dz), 0.0)
	return 1.0 - smoothstep(0.0, feather, d)


## Is this spot flat and open enough to drop a building on?
static func is_buildable(x: float, z: float) -> bool:
	if Vector2(x, z).length() > HALF_SIZE - RIM_BAND - 2.0:
		return false
	# Keep the farm zones for farming — the shared one to the east,
	# and each homestead's own patch.
	if absf(x - FARM_CENTRE.x) < FARM_HALF.x + 1.0 and absf(z - FARM_CENTRE.z) < FARM_HALF.y + 1.0:
		return false
	for hs in HOMESTEADS:
		var f: Vector3 = hs["farm"]
		if absf(x - f.x) < HOMESTEAD_FARM_HALF.x + 1.0 \
		and absf(z - f.z) < HOMESTEAD_FARM_HALF.y + 1.0:
			return false
	if Vector3(x, 0, z).distance_to(PORTAL_POS) < 6.0:
		return false
	return normal(x, z).y > 0.93


## Which homestead is this point in, or -1 for the shared world.
## Used by the signposts today and by the spawn picker later.
static func homestead_at(x: float, z: float) -> int:
	for i in HOMESTEADS.size():
		var p: Vector3 = HOMESTEADS[i]["pos"]
		if Vector2(x - p.x, z - p.z).length() <= HOMESTEAD_RADIUS + 4.0:
			return i
	return -1
