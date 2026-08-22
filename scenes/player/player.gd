# =============================================================
# player.gd — the Sprite you control.
# -------------------------------------------------------------
# Movement, the diorama camera, the "what am I looking at" probe,
# and build mode. Animation is done in code by nudging the rig's
# named parts: a breathing bob when idle, a waddle when walking,
# and a squash whenever you do something. Art Bible §2.
#
# No animation files, no state machine — for a character this
# simple, six lines of sin() reads better than an AnimationTree
# and never desyncs.
# =============================================================
class_name Player
extends CharacterBody3D

signal target_changed(label: String, kind: String)
signal wants_shop()
signal wants_bench()
signal wants_quests()
signal build_mode_changed(active: bool)

const SPEED := 5.4
const ACCEL := 14.0
const TURN_SPEED := 11.0
const CAM_DISTANCE := 11.5
const CAM_HEIGHT := 7.4
const BUILD_REACH := 4.2

# Jump. At gravity 24 a launch of 9.0 clears about 1.7m — enough to hop
# a rock or a fence post, not enough to get on a mushroom house roof.
# That ceiling is deliberate: nothing up there is finished yet.
const JUMP_VELOCITY := 9.0
# Two forgiveness windows, both invisible when they work and both the
# difference between "floaty" and "broken" for a seven-year-old:
const COYOTE_TIME := 0.12    # still jumpable just after walking off a ledge
const JUMP_BUFFER := 0.14    # a press just before landing still counts

# The camera rig. Derived from CAM_DISTANCE/CAM_HEIGHT above — a spring
# arm of CAM_LENGTH, pitched CAM_PITCH above the horizon, puts the lens
# in exactly the old place while gaining collision for free.
#   length = sqrt(11.5^2 + 7.4^2)      pitch = atan2(7.4, 11.5)
const CAM_LENGTH := 13.68
const CAM_PITCH := 0.5716          # radians, about 32.8 degrees
const CAM_FOCUS := Vector3(0, 1.3, 0)
const CAM_PROBE := 0.45            # the sphere the arm sweeps
# Never let the lens come closer than this. A spring arm with no floor
# collapses to zero the moment its origin is inside anything, and you
# spend the next ten seconds looking at the back of the Sprite's head.
const CAM_MIN_LENGTH := 6.2
const CAM_RETURN_SPEED := 3.5      # eases back out; snaps in instantly
# Layer 1 = terrain, layer 3 = camera blockers (see world.gd).
const CAM_COLLIDE_MASK := 1 | 4

var world: World
var camera: Camera3D

var _rig: Node3D
var _body: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

var _cam_yaw: float = 0.0
var _cam_pivot: Node3D
var _cam_arm: SpringArm3D
var _pivot_pos: Vector3
var _cam_len: float = CAM_LENGTH
var _t: float = 0.0
var _stride: float = 0.0
var _squash: float = 0.0
var _stretch: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _air_time: float = 0.0
var _was_on_floor: bool = true
# Set for one frame when we jump, so Net can send "they hopped" once
# instead of streaming the whole arc. See remote_player.gd.
var _net_hopped: bool = false
var _current_target: Dictionary = {}
var _build_mode: bool = false
var _ghost: Node3D
var _ghost_yaw: float = 0.0
var _gravity: float = 24.0


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))

	var shape := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.42
	caps.height = 1.5
	shape.shape = caps
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)

	_rig = Props.sprite_body()
	add_child(_rig)
	_body = _rig.get_node("Body")
	_arm_l = _body.get_node("ArmL")
	_arm_r = _body.get_node("ArmR")
	_leg_l = _body.get_node("LegL")
	_leg_r = _body.get_node("LegR")

	# A soft warm bounce light so the Sprite never falls into shadow.
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.SUN_COLOR
	lamp.light_energy = 0.45
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, 1.6, 0.8)
	add_child(lamp)

	_build_camera_rig()


# The camera hangs off a SpringArm3D rather than being flown by hand.
# The arm sweeps a sphere from the Sprite's chest outward; if anything
# on the terrain or blocker layer is in the way it pulls the lens in to
# the contact point. That is what stops the market stall and the big
# mushroom caps from filling the screen when you walk behind them.
func _build_camera_rig() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CameraPivot"

	_cam_arm = SpringArm3D.new()
	_cam_arm.name = "CameraArm"
	_cam_arm.spring_length = CAM_LENGTH
	_cam_arm.margin = 0.35
	_cam_arm.collision_mask = CAM_COLLIDE_MASK
	var probe := SphereShape3D.new()
	probe.radius = CAM_PROBE
	_cam_arm.shape = probe
	_cam_arm.rotation.x = -CAM_PITCH
	_cam_pivot.add_child(_cam_arm)

	# The arm is used as a SENSOR only — we read get_hit_length() and
	# place the camera ourselves. Letting the arm parent the camera
	# means no minimum distance and no control over how it eases back
	# out, both of which we need.
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 46.0
	camera.current = true
	_cam_pivot.add_child(camera)

	_pivot_pos = global_position + CAM_FOCUS
	_cam_pivot.position = _pivot_pos
	_cam_pivot.rotation.y = _cam_yaw
	get_parent().call_deferred("add_child", _cam_pivot)
	# Never let the arm collide with the Sprite it is attached to.
	_cam_arm.add_excluded_object(get_rid())


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Movement is camera-relative: "up" always means "away from you".
	var basis_dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, _cam_yaw)
	# A full belly makes the Sprite bouncy; an empty one makes it trudge.
	var speed := SPEED * GameState.speed_multiplier()
	var wish := basis_dir.normalized() * speed if basis_dir.length() > 0.05 else Vector3.ZERO

	velocity.x = move_toward(velocity.x, wish.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, wish.z, ACCEL * delta)

	# --- Jump -----------------------------------------------------
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	_jump_buffer = maxf(0.0, _jump_buffer - delta)

	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)
		_air_time += delta
		velocity.y -= _gravity * delta

	if _jump_buffer > 0.0 and _coyote > 0.0:
		# A full belly springs higher. Damped to 60% of the speed bonus
		# because jump HEIGHT goes with the square of launch velocity —
		# a 12% faster Sprite would otherwise jump 25% higher.
		var boost := 1.0 + (GameState.speed_multiplier() - 1.0) * 0.6
		velocity.y = JUMP_VELOCITY * boost
		_jump_buffer = 0.0
		_coyote = 0.0
		_stretch = 1.0
		_net_hopped = true
		Sfx.play("jump")
	elif on_floor and velocity.y <= 0.0:
		velocity.y = -1.0          # stay stuck to slopes

	move_and_slide()

	# Landing. The threshold skips the thud on a one-frame stumble off
	# a pebble, which otherwise chirps constantly while walking.
	var landed := is_on_floor()
	if landed and not _was_on_floor and _air_time > 0.12:
		_squash = 1.0
		Sfx.play("land")
	if landed:
		_air_time = 0.0
	_was_on_floor = landed

	if wish.length() > 0.1:
		var want_yaw := atan2(-wish.x, -wish.z)
		_rig.rotation.y = lerp_angle(_rig.rotation.y, want_yaw, TURN_SPEED * delta)

	# Tell the others where we are. Net decides how often; a jump is
	# flagged so it goes out immediately rather than waiting for the
	# next tick, because a hop that arrives late has already landed.
	Net.send_my_position(delta, global_position, _rig.rotation.y, _net_hopped)
	_net_hopped = false


func _process(delta: float) -> void:
	_t += delta
	_animate(delta)
	_update_camera(delta)
	_update_target()
	if _build_mode:
		_update_ghost()


# --- Animation ------------------------------------------------
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var airborne := not is_on_floor()
	var moving := speed > 0.4 and not airborne
	_stride += delta * (11.0 if moving else 0.0)

	if airborne:
		# Hop pose: knees tucked, arms up. Legs mid-stride while
		# airborne read as running on air, which looks wrong instantly.
		var e := 10.0 * delta
		_leg_l.rotation.x = lerp(_leg_l.rotation.x, -0.55, e)
		_leg_r.rotation.x = lerp(_leg_r.rotation.x, -0.30, e)
		_arm_l.rotation.x = lerp(_arm_l.rotation.x, -1.15, e)
		_arm_r.rotation.x = lerp(_arm_r.rotation.x, -1.05, e)
		_body.rotation.z = lerp(_body.rotation.z, 0.0, e)
		_body.position.y = lerp(_body.position.y, 0.06, e)
	elif moving:
		# Waddle: hips roll, arms counter-swing, a bouncy step.
		var swing := sin(_stride)
		_leg_l.rotation.x = swing * 0.62
		_leg_r.rotation.x = -swing * 0.62
		_arm_l.rotation.x = -swing * 0.5
		_arm_r.rotation.x = swing * 0.5
		_body.rotation.z = sin(_stride * 0.5) * 0.09
		_body.position.y = absf(sin(_stride)) * 0.11
	else:
		# Idle: gentle breathing bob.
		var ease_out := 8.0 * delta
		_leg_l.rotation.x = lerp(_leg_l.rotation.x, 0.0, ease_out)
		_leg_r.rotation.x = lerp(_leg_r.rotation.x, 0.0, ease_out)
		_arm_l.rotation.x = lerp(_arm_l.rotation.x, sin(_t * 1.5) * 0.05, ease_out)
		_arm_r.rotation.x = lerp(_arm_r.rotation.x, -sin(_t * 1.5) * 0.05, ease_out)
		_body.rotation.z = lerp(_body.rotation.z, 0.0, ease_out)
		_body.position.y = lerp(_body.position.y, 0.03 * sin(_t * 1.8), ease_out)

	# Squash and stretch. Stretch fires on take-off, squash on landing
	# and on every interaction. They can overlap on a fast bounce, so
	# blend both into one scale rather than letting either win.
	var e_squash := 0.0
	var e_stretch := 0.0
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta * 3.4)
		e_squash = _squash * _squash
	if _stretch > 0.0:
		_stretch = maxf(0.0, _stretch - delta * 2.8)
		e_stretch = _stretch * _stretch
	_body.scale = Vector3(
		1.0 + 0.18 * e_squash - 0.11 * e_stretch,
		1.0 - 0.22 * e_squash + 0.20 * e_stretch,
		1.0 + 0.18 * e_squash - 0.11 * e_stretch)


# --- Camera ---------------------------------------------------
func _update_camera(delta: float) -> void:
	if Input.is_action_pressed("cam_left"):
		_cam_yaw += delta * 1.8
	if Input.is_action_pressed("cam_right"):
		_cam_yaw -= delta * 1.8

	if _cam_pivot == null or not _cam_pivot.is_inside_tree():
		return

	# Only the pivot is smoothed. The arm resolves collision instantly,
	# which is correct: a lens that eases *into* a wall is worse than one
	# that snaps clear of it.
	var want := global_position + CAM_FOCUS
	# Follow sideways briskly, vertically lazily. Matching the Sprite's
	# height 1:1 makes the whole world bob with every jump; lagging it
	# keeps the horizon steady and reads as a camera operator, not a hat.
	var k_xz := clampf(delta * 6.0, 0.0, 1.0)
	var k_y := clampf(delta * 2.6, 0.0, 1.0)
	_pivot_pos.x = lerp(_pivot_pos.x, want.x, k_xz)
	_pivot_pos.z = lerp(_pivot_pos.z, want.z, k_xz)
	_pivot_pos.y = lerp(_pivot_pos.y, want.y, k_y)
	_cam_pivot.global_position = _pivot_pos
	_cam_pivot.rotation.y = _cam_yaw
	_place_camera(delta)


# Pull in fast, ease back out. Getting shoved out of a wall should be
# instant — you never notice it. Drifting back out should be slow, or
# every bush you brush past punches the camera.
func _place_camera(delta: float) -> void:
	var hit: float = clampf(_cam_arm.get_hit_length(), CAM_MIN_LENGTH, CAM_LENGTH)
	if hit < _cam_len:
		_cam_len = hit
	else:
		_cam_len = lerp(_cam_len, hit, clampf(delta * CAM_RETURN_SPEED, 0.0, 1.0))
	camera.position = _cam_arm.transform.basis * Vector3(0.0, 0.0, _cam_len)
	camera.look_at(_cam_pivot.global_position, Vector3.UP)


## Make the Sprite jump right now, ignoring the ground check.
## Used by the screenshot harness; also the hook for a future
## bounce-pad or a scripted moment.
func hop(scale_f: float = 1.0) -> void:
	velocity.y = JUMP_VELOCITY * scale_f
	_stretch = 1.0
	_was_on_floor = false
	Sfx.play("jump")


## Point the Sprite at a world yaw immediately, skipping the turn
## easing. For warps, cutscenes, and the screenshot harness.
func set_facing(yaw: float) -> void:
	_rig.rotation.y = yaw


## Teleport the rig to wherever the Sprite is, with no easing.
## Used after a warp and by the screenshot harness.
func snap_camera() -> void:
	_pivot_pos = global_position + CAM_FOCUS
	_cam_len = CAM_LENGTH
	if _cam_pivot and _cam_pivot.is_inside_tree():
		_cam_pivot.global_position = _pivot_pos
		_cam_pivot.rotation.y = _cam_yaw
		_place_camera(1.0)


# --- What am I standing next to? ------------------------------
func _update_target() -> void:
	if world == null:
		return
	if _build_mode:
		return
	var it := world.nearest_interactable(global_position)
	if it == _current_target:
		return
	_current_target = it
	target_changed.emit(_target_label(it), String(it.get("kind", "")))


func _target_label(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	if String(it["kind"]) == "plot":
		var p: Dictionary = GameState.plots[int(it["index"])]
		match int(p["state"]):
			GameState.Soil.UNTILLED: return "Turn over the soil"
			GameState.Soil.TILLED:   return "Plant a %s seed" % Defs.CROPS[GameState.selected_seed]["name"]
			GameState.Soil.PLANTED:  return "Water it"
			GameState.Soil.GROWING:  return "Growing..."
			GameState.Soil.READY:    return "Harvest the %s!" % Defs.CROPS[String(p["crop"])]["name"]
	if String(it["kind"]) == "hive":
		var pct := int(GameState.hive_progress(int(it["index"])) * 100.0)
		return "Take the honey" if pct >= 100 else "Bee Hive — %d%% full" % pct
	return String(it["label"])


# --- Input ----------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_do_interact()
	elif event.is_action_pressed("eat"):
		GameState.eat_something()
		_squash = 1.0
	elif event.is_action_pressed("cycle_seed"):
		if _build_mode:
			_cycle_build_item()
		else:
			GameState.cycle_seed()
			_current_target = {}     # relabel the prompt with the new seed
	elif event.is_action_pressed("build_house"):
		_toggle_build_mode()
	elif event.is_action_pressed("reset_save"):
		GameState.wipe_and_restart()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_do_interact()


func _do_interact() -> void:
	if _build_mode:
		_confirm_build()
		return
	if _current_target.is_empty():
		return
	_squash = 1.0
	match String(_current_target["kind"]):
		"plot":
			GameState.interact_plot(int(_current_target["index"]))
			_current_target = {}
		"gather":
			GameState.gather(int(_current_target["index"]),
				String(_current_target["material"]))
			_current_target = {}
		"bench":
			wants_bench.emit()
		"hive":
			GameState.collect_hive(int(_current_target["index"]))
			_current_target = {}
		"stall":
			wants_shop.emit()
		"board":
			wants_quests.emit()
		"sprout":
			_talk_to_sprout()
		"portal":
			_examine_portal()
		"homestead":
			_read_signpost(int(_current_target["index"]))


func _talk_to_sprout() -> void:
	var step := GameState.onboarding_step()
	if step.is_empty():
		GameState.say.emit("Old Sprout",
			"Warm afternoon, isn't it. Keep the soil watered and the belly full, little sprite.")
		return
	GameState.say.emit(String(step["who"]) if String(step["who"]) != "" else "Old Sprout",
		String(step["text"]))
	# The talking steps advance on the conversation; the doing steps
	# advance when you actually do them.
	if String(step["id"]) in ["welcome", "gift", "wait", "free"]:
		GameState.advance_onboarding_manually()


## The signpost at a homestead. Tells you where you are and how
## your own soil is doing, so a clearing on the far side of the
## map is a place with a name rather than a patch of grass.
func _read_signpost(index: int) -> void:
	var hs: Dictionary = Terrain.HOMESTEADS[index]
	var owner := String(GameState.homestead_owner[index]) \
		if index < GameState.homestead_owner.size() else ""

	# Nobody has taken it: pressing E here is how you claim it. That
	# is the whole flow -- walk somewhere you like, press the button
	# you already press for everything else.
	if owner == "":
		GameState.request_claim(index)
		return

	if owner != Net.player_name and Net.player_name != "":
		GameState.say.emit(String(hs["name"]),
			"%s's clearing. You are welcome to help — water anything you like." % owner)
		return

	var first := GameState.PLOT_COLS * GameState.PLOT_ROWS \
		+ index * GameState.HOMESTEAD_COLS * GameState.HOMESTEAD_ROWS
	var last := first + GameState.HOMESTEAD_COLS * GameState.HOMESTEAD_ROWS
	var working := 0
	var ripe := 0
	for i in range(first, mini(last, GameState.plots.size())):
		var st: int = int(GameState.plots[i]["state"])
		if st != GameState.Soil.UNTILLED:
			working += 1
		if st == GameState.Soil.READY:
			ripe += 1
	var line := "Untouched ground. Turn over some soil and make it yours."
	if ripe > 0:
		line = "%d of your %d patches are ready to pull." % [ripe, working]
	elif working > 0:
		line = "%d patches worked. Nothing ripe yet — give it time." % working
	GameState.say.emit(String(hs["name"]), line)


func _examine_portal() -> void:
	if GameState.portal_open:
		GameState.say.emit("", "The roots have parted. Tendril Valley waits beyond — in the next update.")
	else:
		var left: int = Defs.PORTAL_QUESTS_REQUIRED - GameState.quests_done.size()
		GameState.say.emit("", "Something stirs beyond... The roots are knotted tight. (%d more quests)" % maxi(left, 0))


# --- Build mode -----------------------------------------------
# You place what you have crafted, not what you can afford. Press 3 to
# take something out of the build bag, 2 to flick to the next thing,
# E to put it down.
func _toggle_build_mode() -> void:
	_build_mode = not _build_mode
	if _build_mode:
		if GameState.total_in_bag() <= 0:
			_build_mode = false
			Sfx.play("deny")
			GameState.toast.emit("Nothing to place — craft something at the workbench",
				Palette.UI_WARN)
			return
		if GameState.bag_count(GameState.selected_build) <= 0:
			GameState.cycle_build()
		_spawn_ghost()
		_current_target = {}
		target_changed.emit("", "")
	else:
		_clear_ghost()
	build_mode_changed.emit(_build_mode)


func _cycle_build_item() -> void:
	if GameState.placeable_ids().size() <= 1:
		return
	GameState.cycle_build()
	_spawn_ghost()
	build_mode_changed.emit(true)
	Sfx.play("pop")


func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null


## The see-through preview. Same Props call as the real thing, so a
## ghost can never disagree with what you end up placing.
func _spawn_ghost() -> void:
	_clear_ghost()
	var id := GameState.selected_build
	if not Defs.RECIPES.has(id):
		return
	# Same lookup the real thing uses, so a ghost can never disagree
	# with what you end up placing — and a craftable your kids add gets
	# a working preview for free.
	_ghost = Props.build(String(Defs.RECIPES[id].get("build", "")))
	if _ghost == null:
		return
	_apply_ghost_alpha(_ghost, 0.45)
	get_parent().add_child(_ghost)


func _update_ghost() -> void:
	if _ghost == null:
		return
	var forward := -_rig.global_transform.basis.z
	var spot := global_position + forward * BUILD_REACH
	_ghost.position = Terrain.point(spot.x, spot.z)
	_ghost_yaw = rad_to_deg(_rig.rotation.y)
	_ghost.rotation_degrees.y = _ghost_yaw
	var ok := GameState.placement_problem(
		GameState.selected_build, spot.x, spot.z, global_position) == ""
	_tint_ghost(_ghost, Palette.MOSS if ok else Palette.DEEP_RED)


func _confirm_build() -> void:
	if _ghost == null:
		return
	var p := _ghost.position
	var id := GameState.selected_build
	if GameState.place_build(id, p.x, p.z, _ghost_yaw, global_position):
		_squash = 1.0
		# Still holding more of the same? Stay in build mode and keep
		# going — laying a fence one post at a time is the whole point.
		if GameState.bag_count(id) > 0:
			_spawn_ghost()
			build_mode_changed.emit(true)
		elif GameState.total_in_bag() > 0:
			GameState.cycle_build()
			_spawn_ghost()
			build_mode_changed.emit(true)
		else:
			_toggle_build_mode()


func _apply_ghost_alpha(node: Node, a: float) -> void:
	for child in node.get_children():
		if child is Light3D:
			(child as Light3D).visible = false
		if child is MeshInstance3D:
			var m := (child as MeshInstance3D).material_override as ShaderMaterial
			if m:
				(child as MeshInstance3D).material_override = ClayKit.to_transparent(m, a)
		_apply_ghost_alpha(child, a)


func _tint_ghost(node: Node, col: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var m := (child as MeshInstance3D).material_override as ShaderMaterial
			if m:
				m.set_shader_parameter("emission_color", col)
				m.set_shader_parameter("emission_strength", 0.5)
		_tint_ghost(child, col)
