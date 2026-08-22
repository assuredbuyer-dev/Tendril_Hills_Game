# =============================================================
# remote_player.gd — somebody else's Sprite, seen from here.
# -------------------------------------------------------------
# One of these per other player. It is deliberately NOT a
# CharacterBody3D: it has no physics, no collision and no rules.
# It is a puppet that moves where the network says, because the
# machine that owns that Sprite has already decided everything and
# a second opinion here would only fight it.
#
# SMOOTHING: positions arrive 15 times a second, and the game draws
# 60. Snapping to each one looks like a slideshow, so the puppet
# eases toward the last known position instead. It runs a frame or
# two behind reality, which nobody notices and which is the
# standard trade in every game that does this.
# =============================================================
class_name RemotePlayer
extends Node3D

const LERP_SPEED := 12.0
const HOP_HEIGHT := 1.1
const HOP_TIME := 0.42
const NAME_HEIGHT := 1.85

var peer_id: int = 0

var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _body: Node3D
var _label: Label3D
var _hop_t: float = 1.0
var _squash: float = 0.0


func setup(id: int, display_name: String, tint: Color) -> void:
	peer_id = id
	name = "Remote%d" % id

	# The same sculpt the local player uses, so nobody looks like a
	# second-class citizen in somebody else's world.
	_body = Props.sprite_body()
	add_child(_body)
	_tint(tint)

	# The name floats above them and always faces you. This is the
	# one place billboarding is right: a name you have to walk around
	# to read is not a name, it is a puzzle.
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 96
	_label.pixel_size = 0.0032
	_label.modulate = Palette.UI_TEXT
	_label.outline_size = 28
	_label.outline_modulate = Palette.UI_PANEL
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true          # never hidden behind a mushroom
	_label.position = Vector3(0, NAME_HEIGHT, 0)
	_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_label)


## A wash of the player's homestead colour over the tunic, so you can
## tell at a glance whose Sprite is wandering across your field.
func _tint(tint: Color) -> void:
	for child in _body.get_children():
		if not (child is MeshInstance3D):
			continue
		var mat := (child as MeshInstance3D).material_override as ShaderMaterial
		if mat == null:
			continue
		var dup := mat.duplicate() as ShaderMaterial
		dup.set_shader_parameter("rim_color", tint)
		dup.set_shader_parameter("rim_strength", 0.34)
		(child as MeshInstance3D).material_override = dup


func set_display_name(n: String) -> void:
	if _label:
		_label.text = n


func move_to(pos: Vector3, yaw: float, hopped: bool) -> void:
	_target_pos = pos
	_target_yaw = yaw
	if hopped and _hop_t >= 1.0:
		_hop_t = 0.0
	# First packet: appear where they are rather than sliding in from
	# the world origin, which looks like they were fired out of a gun.
	if global_position.distance_to(pos) > 12.0:
		global_position = pos


func _process(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, minf(1.0, LERP_SPEED * delta))
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, LERP_SPEED * delta))

	# The hop arc is played locally from a single "they jumped" flag
	# rather than streamed. Sending sixty heights a second to describe
	# a curve both machines already know is waste.
	if _hop_t < 1.0:
		_hop_t = minf(1.0, _hop_t + delta / HOP_TIME)
		var arc := sin(_hop_t * PI)
		_body.position.y = arc * HOP_HEIGHT
		_body.scale = Vector3(1.0 - arc * 0.12, 1.0 + arc * 0.18, 1.0 - arc * 0.12)
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, minf(1.0, 10.0 * delta))
		_body.scale = _body.scale.lerp(Vector3.ONE, minf(1.0, 10.0 * delta))
