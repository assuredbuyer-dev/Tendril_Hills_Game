# =============================================================
# clay_kit.gd — the sculpting toolkit.
# -------------------------------------------------------------
# Every object in Tendril Hills is thumbed out of ONE primitive:
# the superellipsoid. Change two exponents and the same generator
# gives you a rounded cube (houses, chests, fences), an egg
# (heads, bodies), a squashed dome (mushroom caps), or a pebble.
#
# Why this matters: Art Bible §4.1 says "no sharp corners
# anywhere". Godot's BoxMesh has eight of them. This does not.
#
# Nothing here needs an art asset. When real Tripo3D models
# arrive, you swap ClayKit.blob(...) for a loaded .glb and the
# rest of the game does not notice — every builder returns a
# plain MeshInstance3D.
# =============================================================
class_name ClayKit
extends RefCounted

const SHADER_PATH := "res://art/clay.gdshader"
const SHADER_ALPHA_PATH := "res://art/clay_alpha.gdshader"

static var _shader: Shader
static var _shader_alpha: Shader
static var _mesh_cache: Dictionary = {}


static func _clay_shader(transparent: bool) -> Shader:
	if transparent:
		if _shader_alpha == null:
			_shader_alpha = load(SHADER_ALPHA_PATH) as Shader
		return _shader_alpha
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


# --- Materials -----------------------------------------------

## Build a clay ShaderMaterial. `opts` keys (all optional):
##   gloss, rim, wobble, grain, noise_scale, emission, emission_strength,
##   alpha, vertex_color, wrap, segments
## Passing alpha < 1 automatically switches to the transparent shader.
static func material(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var a: float = opts.get("alpha", 1.0)
	var m := ShaderMaterial.new()
	m.shader = _clay_shader(a < 0.999)
	m.set_shader_parameter("clay_color", color)
	m.set_shader_parameter("rim_color", Palette.CREAM)
	m.set_shader_parameter("rim_strength", opts.get("rim", 0.16))
	m.set_shader_parameter("wobble", opts.get("wobble", 0.02))
	m.set_shader_parameter("grain", opts.get("grain", 0.10))
	m.set_shader_parameter("noise_scale", opts.get("noise_scale", 7.0))
	m.set_shader_parameter("gloss", opts.get("gloss", 0.0))
	m.set_shader_parameter("wrap_amount", opts.get("wrap", 0.38))
	m.set_shader_parameter("emission_color", opts.get("emission", Color.BLACK))
	m.set_shader_parameter("emission_strength", opts.get("emission_strength", 0.0))
	m.set_shader_parameter("vertex_color_amount", opts.get("vertex_color", 0.0))
	m.set_shader_parameter("alpha", a)
	if a < 0.999:
		m.render_priority = 1
	return m


## Return a see-through copy of a clay material — used by build mode.
static func to_transparent(src: ShaderMaterial, a: float) -> ShaderMaterial:
	var m := src.duplicate() as ShaderMaterial
	m.shader = _clay_shader(true)
	m.set_shader_parameter("alpha", a)
	m.render_priority = 2
	return m


# --- The one primitive ---------------------------------------

## Superellipsoid surface.
##   n1 = 1.0, n2 = 1.0  -> ellipsoid (heads, berries, pebbles)
##   n1 = 0.3, n2 = 0.3  -> rounded cube (houses, chests, planters)
##   n1 = 0.4, n2 = 1.0  -> rounded cylinder / stalk
##   n1 = 1.6, n2 = 1.0  -> pinched top (mushroom cap, teardrop)
## `size` is the full width/height/depth of the bounding box.
static func superellipsoid(size: Vector3, n1: float = 1.0, n2: float = 1.0, segments: int = 16) -> ArrayMesh:
	var key := "%s|%.2f|%.2f|%d" % [str(size.snapped(Vector3(0.001, 0.001, 0.001))), n1, n2, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings := segments
	var radials := segments * 2
	var half := size * 0.5

	var pts: Array = []
	for i in rings + 1:
		var v: float = lerp(-PI * 0.5, PI * 0.5, float(i) / float(rings))
		var row: Array = []
		for j in radials + 1:
			var u: float = lerp(-PI, PI, float(j) / float(radials))
			row.append(_super_point(u, v, n1, n2) * half)
		pts.append(row)

	for i in rings:
		for j in radials:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j + 1]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i + 1][j]
			# UVs are cheap here but let real textures land later.
			var ua := Vector2(float(j) / radials, float(i) / rings)
			var ub := Vector2(float(j + 1) / radials, float(i) / rings)
			var uc := Vector2(float(j + 1) / radials, float(i + 1) / rings)
			var ud := Vector2(float(j) / radials, float(i + 1) / rings)
			if a.distance_squared_to(b) > 0.0000001:
				st.set_uv(ua); st.add_vertex(a)
				st.set_uv(ub); st.add_vertex(b)
				st.set_uv(uc); st.add_vertex(c)
			if c.distance_squared_to(d) > 0.0000001:
				st.set_uv(ua); st.add_vertex(a)
				st.set_uv(uc); st.add_vertex(c)
				st.set_uv(ud); st.add_vertex(d)

	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


static func _super_point(u: float, v: float, n1: float, n2: float) -> Vector3:
	var cv := _signed_pow(cos(v), n1)
	var sv := _signed_pow(sin(v), n1)
	var cu := _signed_pow(cos(u), n2)
	var su := _signed_pow(sin(u), n2)
	return Vector3(cv * cu, sv, cv * su)


static func _signed_pow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


# --- Node builders (what world code actually calls) ----------

static func _mi(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	return n


## Soft egg / pebble / berry.
static func blob(size: Vector3, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return _mi(superellipsoid(size, 1.0, 1.0, int(opts.get("segments", 14))), material(color, opts), pos)


## Rounded cube — walls, chests, planters, signs. No sharp corners.
static func slab(size: Vector3, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return _mi(superellipsoid(size, 0.32, 0.32, int(opts.get("segments", 14))), material(color, opts), pos)


## Rounded cylinder — stems, trunks, posts, tool handles.
static func stalk(size: Vector3, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	return _mi(superellipsoid(size, 0.42, 1.0, int(opts.get("segments", 14))), material(color, opts), pos)


## Squashed dome sitting ON the ground — mushroom caps, hills, loaves.
## Gets a touch of gloss by default per Art Bible §4.1
## ("slight gloss on mushroom caps only").
static func dome(radius: float, height: float, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var o := opts.duplicate()
	if not o.has("gloss"):
		o["gloss"] = 0.3
	var steps := 10
	var profile := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		# Slightly flared skirt then a soft crown — reads as hand-pressed.
		var r: float = radius * pow(cos(t * PI * 0.5), 0.65)
		profile.append(Vector2(r, height * sin(t * PI * 0.5)))
	return lathe(profile, color, pos, o)


## Lathe: spin a 2D profile around the Y axis.
## `profile` is a list of Vector2(radius, height) from bottom to top.
## This is how carrots, watering cans, tree trunks and roof spires
## get made — anything with a silhouette worth drawing.
static func lathe(profile: PackedVector2Array, color: Color, pos := Vector3.ZERO, opts: Dictionary = {}) -> MeshInstance3D:
	var segments: int = int(opts.get("segments", 20))
	var key := "lathe|%s|%d" % [str(profile), segments]
	var mesh: ArrayMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in profile.size() - 1:
			var p0 := profile[i]
			var p1 := profile[i + 1]
			for j in segments:
				var a0: float = TAU * float(j) / float(segments)
				var a1: float = TAU * float(j + 1) / float(segments)
				var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
				var v10 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
				var v01 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
				var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
				if p0.x > 0.0001:
					st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v11)
				if p1.x > 0.0001:
					st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v01)
		# Cap the ends if the profile does not already close to a point.
		_cap(st, profile[0], segments, false)
		_cap(st, profile[profile.size() - 1], segments, true)
		st.generate_normals()
		mesh = st.commit()
		_mesh_cache[key] = mesh
	return _mi(mesh, material(color, opts), pos)


static func _cap(st: SurfaceTool, edge: Vector2, segments: int, up: bool) -> void:
	if edge.x <= 0.0001:
		return
	var centre := Vector3(0, edge.y, 0)
	for j in segments:
		var a0: float = TAU * float(j) / float(segments)
		var a1: float = TAU * float(j + 1) / float(segments)
		var v0 := Vector3(cos(a0) * edge.x, edge.y, sin(a0) * edge.x)
		var v1 := Vector3(cos(a1) * edge.x, edge.y, sin(a1) * edge.x)
		if up:
			st.add_vertex(centre); st.add_vertex(v0); st.add_vertex(v1)
		else:
			st.add_vertex(centre); st.add_vertex(v1); st.add_vertex(v0)


## A leaf: flattened teardrop, tilted outward from a stem.
static func leaf(length: float, color: Color, angle_deg: float, yaw_deg: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(0, yaw_deg, 0)
	var arm := Node3D.new()
	arm.rotation_degrees = Vector3(-angle_deg, 0, 0)
	var blade := blob(
		Vector3(length * 0.42, length * 0.14, length),
		color,
		Vector3(0, 0, length * 0.5),
		{"wobble": 0.05, "grain": 0.18, "noise_scale": 12.0}
	)
	arm.add_child(blade)
	pivot.add_child(arm)
	return pivot


## Small helper: scatter n children around a ring.
static func ring_positions(count: int, radius: float, y: float = 0.0, phase: float = 0.0) -> Array:
	var out: Array = []
	for i in count:
		var a: float = phase + TAU * float(i) / float(count)
		out.append(Vector3(cos(a) * radius, y, sin(a) * radius))
	return out
