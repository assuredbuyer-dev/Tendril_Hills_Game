# =============================================================
# terrain.gd — one source of truth for "how high is the ground?"
# -------------------------------------------------------------
# Both the terrain mesh AND everything standing on it (plots,
# houses, trees, the player's spawn) ask this same function, so
# nothing ever floats or sinks. Change the landscape here and the
# whole world moves with it.
#
# Layout follows World Design §2:
#   village centre  = middle (flat, buildable)
#   farm zone       = east   (flat, tillable)
#   root portal     = west
#   spawn           = south
#   forest edge     = north + the outer ring (decorative border)
# =============================================================
class_name Terrain
extends RefCounted

const HALF_SIZE := 34.0          # world spans -34..34 on X and Z
const ROLL_HEIGHT := 1.25        # how tall the gentle hills are

const VILLAGE_CENTRE := Vector3(0, 0, 0)
const VILLAGE_RADIUS := 11.0
const FARM_CENTRE := Vector3(17.0, 0, 1.0)
const FARM_HALF := Vector2(7.0, 6.0)
const PORTAL_POS := Vector3(-19.0, 0, -2.0)
const SPAWN_POS := Vector3(0, 0, 12.0)

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
	var rim := smoothstep(HALF_SIZE - 14.0, HALF_SIZE, d)
	h += rim * 5.5

	# Flatten the two zones the player builds on.
	h = lerp(h, 0.0, _flatten_circle(x, z, VILLAGE_CENTRE, VILLAGE_RADIUS, 5.0))
	h = lerp(h, 0.0, _flatten_rect(x, z, FARM_CENTRE, FARM_HALF, 3.5))
	# A level apron in front of the portal so the archway sits true.
	h = lerp(h, 0.35, _flatten_circle(x, z, PORTAL_POS, 4.0, 3.0))
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
	if Vector2(x, z).length() > HALF_SIZE - 15.0:
		return false
	# Keep the farm zone for farming.
	if absf(x - FARM_CENTRE.x) < FARM_HALF.x + 1.0 and absf(z - FARM_CENTRE.z) < FARM_HALF.y + 1.0:
		return false
	if Vector3(x, 0, z).distance_to(PORTAL_POS) < 6.0:
		return false
	return normal(x, z).y > 0.93
