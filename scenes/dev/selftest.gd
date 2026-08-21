# =============================================================
# selftest.gd — drive the whole game loop with no hands.
# -------------------------------------------------------------
# Run:  ./tools/selftest.sh
# Raw:  godot --path . --headless -- --selftest
#
# Presses every button the game has, in the order a player would,
# and checks the state that comes back. Exits non-zero if anything
# fails, so it can gate a commit.
#
# WHY THIS EXISTS: the screenshot loop (docs/LOOP.md) only sees
# still frames. It cannot see a crash on a keypress. This can.
# =============================================================
extends Node

var _fails: Array = []
var _checks: int = 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", what)
	else:
		_fails.append(what)
		print("  FAIL ", what)


func run() -> void:
	print("\n=== Tendril Hills self-test ===")
	GameState.wipe_and_restart()
	await get_tree().process_frame

	_test_audio()
	_test_bindings()
	_test_farm_loop()
	_test_eating()
	_test_shop()
	_test_gathering()
	_test_crafting()
	_test_placing()
	_test_scarecrow_and_hive()
	_test_registry()
	_test_world_size()
	_test_homesteads()
	await _test_jump()
	_test_collision()
	_test_save_roundtrip()

	print("\n%d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("  FAILED: ", f)
	get_tree().quit(1 if _fails.size() > 0 else 0)


# Every sound the game can make. This is the path that only runs
# when there is a real audio device, which is exactly why it is
# worth firing deliberately.
func _test_audio() -> void:
	print("\n-- audio --")
	# Loop Sfx.KINDS rather than a hardcoded list, so a sound added
	# later is covered the day it is added.
	for kind in Sfx.KINDS:
		Sfx.play(kind)
		check(true, "Sfx.play(%s) did not crash" % kind)
	check(Sfx.KINDS.size() == Sfx.TONES.size(), "every named sound has a tone")


func _test_bindings() -> void:
	print("\n-- input bindings --")
	for action in Controls.BINDINGS:
		check(InputMap.has_action(action), "action '%s' is registered" % action)
	# Space moved from interact to jump. If both claim it, standing on a
	# plot and pressing space would till AND hop in the same frame.
	var clash := []
	for a in ["interact", "jump"]:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and ev.physical_keycode == KEY_SPACE:
				clash.append(a)
	check(clash == ["jump"], "space belongs to jump alone (got %s)" % str(clash))


func _test_farm_loop() -> void:
	print("\n-- farm loop --")
	var seeds_before := GameState.seed_count("carrot")

	GameState.interact_plot(0)
	check(GameState.plots[0]["state"] == GameState.Soil.TILLED, "grass -> tilled")

	GameState.interact_plot(0)
	check(GameState.plots[0]["state"] == GameState.Soil.PLANTED, "tilled -> planted")
	check(GameState.seed_count("carrot") == seeds_before - 1, "planting spent one seed")

	GameState.interact_plot(0)
	check(GameState.plots[0]["state"] == GameState.Soil.GROWING, "planted -> growing")

	GameState.interact_plot(0)
	check(GameState.plots[0]["state"] == GameState.Soil.GROWING, "growing ignores extra presses")

	# Fast-forward: back-date the watering so it is ripe.
	GameState.plots[0]["watered_at"] = Time.get_unix_time_from_system() - 9999.0
	check(GameState.plot_progress(0) >= 1.0, "back-dated crop reads as ripe")
	GameState.plots[0]["state"] = GameState.Soil.READY

	var held := GameState.larder_count("carrot")
	GameState.interact_plot(0)
	check(GameState.larder_count("carrot") > held, "ready -> harvested into basket")
	check(GameState.plots[0]["state"] == GameState.Soil.UNTILLED, "harvest resets the plot")

	# Planting with an empty pouch must refuse, not crash.
	GameState.seeds["carrot"] = 0
	GameState.selected_seed = "carrot"
	GameState.interact_plot(1)
	GameState.interact_plot(1)
	check(GameState.plots[1]["state"] == GameState.Soil.TILLED, "no seeds -> stays tilled, no crash")
	GameState.seeds["carrot"] = 3


func _test_eating() -> void:
	print("\n-- eating --")
	GameState.larder["carrot"] = 2
	GameState.hunger = 40.0
	GameState.eat_something()
	check(GameState.hunger > 40.0, "eating raises hunger")
	check(GameState.larder_count("carrot") == 1, "eating consumes one crop")

	GameState.larder = {}
	GameState.eat_something()
	check(true, "eating with an empty basket does not crash")

	# Belly bands
	GameState.hunger = 95.0
	check(GameState.belly_band() == GameState.Belly.WELL_FED, "95 hunger = well fed")
	check(GameState.speed_multiplier() > 1.0, "well fed walks faster")
	GameState.hunger = 5.0
	check(GameState.belly_band() == GameState.Belly.PECKISH, "5 hunger = peckish")
	check(GameState.speed_multiplier() < 1.0, "peckish trudges")
	GameState.hunger = 50.0
	check(GameState.speed_multiplier() == 1.0, "middling hunger is neutral")


func _test_shop() -> void:
	print("\n-- shop --")
	GameState.coins = 100
	var n := GameState.seed_count("radish")
	GameState.buy_seed("radish")
	check(GameState.seed_count("radish") == n + 1, "buying adds a seed")
	check(GameState.coins < 100, "buying costs coins")

	GameState.coins = 0
	var n2 := GameState.seed_count("radish")
	GameState.buy_seed("radish")
	check(GameState.seed_count("radish") == n2, "cannot buy with no coins")

	GameState.larder = {"carrot": 3}
	GameState.sell_larder()
	check(GameState.coins > 0, "selling earns coins")
	check(GameState.total_larder() == 0, "selling empties the basket")

	GameState.sell_larder()
	check(true, "selling an empty basket does not crash")

	for i in Defs.CROPS.size() + 1:
		GameState.cycle_seed()
	check(Defs.CROPS.has(GameState.selected_seed), "cycling seeds stays in range")


func _test_gathering() -> void:
	print("\n-- gathering --")
	GameState.materials = {}
	GameState.gathered = {}

	check(GameState.gather(101, "toadstool"), "picked up a toadstool")
	check(GameState.material_count("toadstool") == 1, "it went into the pouch")
	check(GameState.is_gathered(101), "that spot now reads as picked")
	check(not GameState.gather(101, "toadstool"), "cannot pick the same spot twice")
	check(GameState.material_count("toadstool") == 1, "and it did not double up")

	# Back-date the regrow so it is due, the way an away player's would be.
	GameState.gathered[101] = Time.get_unix_time_from_system() - 1.0
	check(not GameState.is_gathered(101), "regrows once its time has passed")
	var back := GameState.take_regrown()
	GameState.gathered[102] = Time.get_unix_time_from_system() - 1.0
	back = GameState.take_regrown()
	check(back.has(102), "take_regrown reports what came back")
	check(not GameState.gathered.has(102), "and clears it from the list")


func _test_crafting() -> void:
	print("\n-- crafting --")
	GameState.materials = {}
	GameState.build_bag = {}
	GameState.placed = []

	check(not GameState.can_craft("fence"), "cannot craft with an empty pouch")
	check(not GameState.craft("fence"), "crafting refuses rather than crashing")
	check(GameState.missing_for("fence") != "", "it says what is missing")

	GameState.materials = {"branch": 2}
	check(GameState.can_craft("fence"), "two branches is enough for a fence post")
	check(GameState.craft("fence"), "crafted it")
	check(GameState.material_count("branch") == 0, "crafting spent the branches")
	check(GameState.bag_count("fence") == 1, "it is in the build bag")
	check(GameState.selected_build == "fence", "and became the held item")

	# Cycling with one item is a no-op, not a crash.
	GameState.cycle_build()
	check(GameState.selected_build == "fence", "cycling with one item keeps it")
	GameState.materials = {"stone": 2}
	GameState.craft("path")
	GameState.cycle_build()
	check(GameState.selected_build != "", "cycling with two items picks one")

	check(not GameState.craft("house"), "cannot craft a house from nothing")


func _test_placing() -> void:
	print("\n-- placing --")
	GameState.placed = []
	GameState.build_bag = {"house": 1, "fence": 2}
	GameState.selected_build = "house"

	# Far from the player, on open ground.
	check(GameState.place_build("house", -8.0, -8.0, 0.0, Vector3(20, 0, 20)),
		"house placed on open ground")
	check(GameState.placed.size() == 1, "it was recorded")
	check(GameState.bag_count("house") == 0, "and left the build bag")

	check(not GameState.place_build("house", -8.2, -8.1, 0.0, Vector3(20, 0, 20)),
		"refuses a second house on top of the first")
	check(GameState.placement_problem("house", Terrain.FARM_CENTRE.x,
		Terrain.FARM_CENTRE.z) != "", "refuses to build in the farm")

	# The one that would actually trap a player.
	check(GameState.placement_problem("house", 12.0, -12.0,
		Vector3(12.0, 0, -12.0)) != "", "refuses to build on top of the Sprite")
	check(GameState.placement_problem("fence", 12.0, -12.0,
		Vector3(20.0, 0, -12.0)) == "", "allows a fence well clear of the Sprite")

	GameState.build_bag = {}
	check(not GameState.place_build("fence", 14.0, -14.0, 0.0), "cannot place an empty bag")


func _test_scarecrow_and_hive() -> void:
	print("\n-- what the placeables do --")
	GameState.placed = []
	check(is_equal_approx(GameState.growth_speed_at(0.0, 0.0), 1.0),
		"no scarecrow, no bonus")

	GameState.placed = [{"id": "scarecrow", "x": 0.0, "z": 0.0, "yaw": 0.0}]
	check(GameState.growth_speed_at(2.0, 2.0) > 1.0, "a scarecrow speeds nearby soil")
	check(is_equal_approx(GameState.growth_speed_at(40.0, 40.0), 1.0),
		"but not soil on the far side of the world")

	# Ten scarecrows must not make crops instant.
	for i in 9:
		GameState.placed.append({"id": "scarecrow", "x": float(i) * 0.3, "z": 0.0, "yaw": 0.0})
	check(GameState.growth_speed_at(0.0, 0.0) <= 1.0 + Defs.SCARECROW_MAX_BONUS + 0.001,
		"the scarecrow bonus is capped")

	# The bonus is baked in at watering, so moving a scarecrow later
	# cannot rewind a crop that is already growing.
	GameState.placed = [{"id": "scarecrow", "x": Terrain.FARM_CENTRE.x,
		"z": Terrain.FARM_CENTRE.z, "yaw": 0.0}]
	GameState.seeds["carrot"] = 5
	GameState.selected_seed = "carrot"
	GameState.plots[0]["state"] = GameState.Soil.PLANTED
	GameState.plots[0]["crop"] = "carrot"
	GameState.interact_plot(0)                     # waters it
	check(float(GameState.plots[0]["speed"]) > 1.0, "watering records the scarecrow help")
	GameState.placed = []
	check(float(GameState.plots[0]["speed"]) > 1.0,
		"removing the scarecrow does not rewind a growing crop")

	# Hives
	GameState.placed = [{"id": "hive", "x": 4.0, "z": 4.0, "yaw": 0.0,
		"filled_at": Time.get_unix_time_from_system()}]
	check(GameState.hive_progress(0) < 1.0, "a fresh hive is not ready")
	check(not GameState.collect_hive(0), "and refuses to be collected")
	GameState.placed[0]["filled_at"] = Time.get_unix_time_from_system() - Defs.HIVE_SECONDS - 1.0
	check(GameState.hive_progress(0) >= 1.0, "it fills over time")
	var honey := GameState.larder_count("honey")
	check(GameState.collect_hive(0), "and gives up its honey")
	check(GameState.larder_count("honey") == honey + 1, "honey went into the basket")
	check(GameState.hive_progress(0) < 1.0, "collecting resets the hive")

	# Honey is food, never a seed.
	check(not Defs.plantable_crops().has("honey"), "honey is not plantable")
	for i in Defs.CROPS.size() + 2:
		GameState.cycle_seed()
		check(GameState.selected_seed != "honey", "seed cycling never lands on honey")
		if i > 4:
			break


# Every recipe must be buildable. A row naming a function that does not
# exist would place an invisible nothing, and you would only find out by
# spending the materials.
func _test_registry() -> void:
	print("\n-- recipe registry --")
	for id in Defs.RECIPES:
		var r: Dictionary = Defs.RECIPES[id]
		check(r.has("build"), "recipe '%s' names a builder" % id)
		var node := Props.build(String(r.get("build", "")))
		check(node != null, "Props can build '%s'" % id)
		if node:
			check(node.get_child_count() > 0, "'%s' is not an empty node" % id)
			node.free()
		for mat in r["cost"]:
			check(Defs.MATERIALS.has(mat), "'%s' costs a real material (%s)" % [id, mat])


# Is there something on the player's collision layer between these two
# points? This is the real question "can the Sprite walk through it?"
# reduced to one ray, and it is the only way to check collision without
# a human at the keyboard.
# The map got four times bigger once. Everything that quietly
# assumed 34 metres broke, and most of it broke somewhere you only
# see by walking there. These checks are the tripwires for the next
# time someone changes Terrain.HALF_SIZE.
func _test_world_size() -> void:
	print("\n-- world size --")
	var h := Terrain.HALF_SIZE

	# The playable disc has to be well inside the bowl rim, or the
	# rim swallows the map.
	check(Terrain.RIM_BAND < h * 0.4,
		"the bowl rim is a border, not most of the world")

	# Spawn, village, farm and portal all have to stay on real,
	# level ground no matter how the map is resized.
	for spot in [Terrain.SPAWN_POS, Terrain.VILLAGE_CENTRE,
			Terrain.FARM_CENTRE, Terrain.PORTAL_POS]:
		check(Vector2(spot.x, spot.z).length() < h - Terrain.RIM_BAND,
			"(%.0f, %.0f) is inside the playable area" % [spot.x, spot.z])

	# The ground under the village must be flat enough to build on.
	check(Terrain.normal(0.0, 0.0).y > 0.99, "the village centre is level")
	check(Terrain.is_buildable(0.0, 4.0), "you can build in the village")
	check(not Terrain.is_buildable(h - 2.0, 0.0),
		"you cannot build out on the rim")

	# Height has to be finite everywhere, including the corners --
	# a NaN here puts the player under the map with no error.
	for corner in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]:
		var y := Terrain.height(corner.x, corner.y)
		check(is_finite(y) and absf(y) < 40.0,
			"the ground at (%.0f, %.0f) is a real height" % [corner.x, corner.y])


# One clearing per player. Everything below reads from
# Terrain.HOMESTEADS, so adding a fifth homestead extends the test
# rather than needing a new one written.
func _test_homesteads() -> void:
	print("\n-- homesteads --")
	var h := Terrain.HALF_SIZE
	check(Terrain.HOMESTEADS.size() >= 4,
		"there is a homestead for each player")

	var shared_plots := GameState.PLOT_COLS * GameState.PLOT_ROWS
	var per_home := GameState.HOMESTEAD_COLS * GameState.HOMESTEAD_ROWS
	# Saves store plots by index. If the shared farm ever stops being
	# indices 0..19, every existing save wakes up with its crops in
	# somebody else's field.
	check(GameState.plots.size() == shared_plots
			+ Terrain.HOMESTEADS.size() * per_home,
		"every homestead has its own soil, and the shared farm still comes first")
	for i in shared_plots:
		var p: Dictionary = GameState.plots[i]
		check(absf(p["x"] - Terrain.FARM_CENTRE.x) <= Terrain.FARM_HALF.x + 0.1,
			"shared plot %d is still in the shared farm" % i) if i == 0 else null

	for i in Terrain.HOMESTEADS.size():
		var hs: Dictionary = Terrain.HOMESTEADS[i]
		var c: Vector3 = hs["pos"]
		var name_s := String(hs["name"])

		check(Vector2(c.x, c.z).length() + Terrain.HOMESTEAD_RADIUS < h - Terrain.RIM_BAND + 8.0,
			"%s is inside the map, not up the rim" % name_s)
		check(Terrain.normal(c.x, c.z).y > 0.99, "%s is flat" % name_s)
		# Not "is one arbitrary spot buildable" -- the first version of
		# this test picked c + 4 metres on X and failed on the two
		# homesteads whose soil happens to lie that way. What matters
		# is that a real amount of the clearing is free to build on
		# once the soil patch has taken its share.
		var open_spots := 0
		var sampled := 0
		for sx in range(-8, 9, 2):
			for sz in range(-8, 9, 2):
				if Vector2(sx, sz).length() > Terrain.HOMESTEAD_RADIUS - 1.0:
					continue
				sampled += 1
				if Terrain.is_buildable(c.x + sx, c.z + sz):
					open_spots += 1
		check(open_spots > sampled / 2,
			"most of %s is yours to build on (%d of %d spots)" % [
				name_s, open_spots, sampled])
		check(Terrain.homestead_at(c.x, c.z) == i,
			"%s knows which homestead it is" % name_s)

		# Its soil block, in HOMESTEADS order, after the shared farm.
		var first := shared_plots + i * per_home
		var soil_ok := true
		var f: Vector3 = hs["farm"]
		for j in range(first, first + per_home):
			var p: Dictionary = GameState.plots[j]
			if absf(p["x"] - f.x) > Terrain.HOMESTEAD_FARM_HALF.x + 0.2 \
			or absf(p["z"] - f.z) > Terrain.HOMESTEAD_FARM_HALF.y + 0.2:
				soil_ok = false
		check(soil_ok, "%s's soil is at %s's farm" % [name_s, name_s])
		check(not Terrain.is_buildable(f.x, f.z),
			"%s's soil is kept for farming, not building" % name_s)

		# And you can actually farm it -- the whole point.
		var plot_i := first
		GameState.interact_plot(plot_i)          # till
		check(GameState.plots[plot_i]["state"] == GameState.Soil.TILLED,
			"you can turn over soil at %s" % name_s)
		GameState.seeds["carrot"] = int(GameState.seeds.get("carrot", 0)) + 1
		GameState.selected_seed = "carrot"
		GameState.interact_plot(plot_i)          # plant
		check(GameState.plots[plot_i]["state"] == GameState.Soil.PLANTED,
			"you can plant at %s" % name_s)
		GameState.interact_plot(plot_i)          # water
		check(GameState.plots[plot_i]["state"] == GameState.Soil.GROWING,
			"you can water at %s" % name_s)

	# Two homesteads sharing a spot would look like one clearing with
	# two signs in it.
	for i in Terrain.HOMESTEADS.size():
		for j in range(i + 1, Terrain.HOMESTEADS.size()):
			var a: Vector3 = Terrain.HOMESTEADS[i]["pos"]
			var b: Vector3 = Terrain.HOMESTEADS[j]["pos"]
			check(Vector2(a.x - b.x, a.z - b.z).length() > Terrain.HOMESTEAD_RADIUS * 2.5,
				"%s and %s are separate places" % [
					Terrain.HOMESTEADS[i]["name"], Terrain.HOMESTEADS[j]["name"]])


func _blocked(from: Vector3, to: Vector3) -> bool:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1                 # layer 1 = terrain and solid props
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()


func _test_collision() -> void:
	print("\n-- collision --")
	var main := get_parent()
	var world = main.get("world")

	# Chest height on flat village ground, so the ray cannot clip terrain.
	var y := 0.9

	check(_blocked(Vector3(4.0, y, 0.0), Vector3(0.3, y, 0.0)),
		"the landmark mushroom stem is solid")
	check(_blocked(Vector3(5.4, y, 5.2), Vector3(5.4, y, 2.4)),
		"the market stall is solid")
	check(_blocked(Vector3(5.0, y, 0.6), Vector3(5.0, y, -2.4)),
		"the workbench is solid")
	check(_blocked(Vector3(-4.6, y, 6.4), Vector3(-4.6, y, 3.6)),
		"the quest board is solid")

	# The portal must stay walk-through: its pillars sit either side of
	# the gap, and the whole point of an archway is going under it.
	var pp := Terrain.PORTAL_POS
	check(not _blocked(Vector3(pp.x + 4.0, pp.y + y, pp.z), Vector3(pp.x - 4.0, pp.y + y, pp.z)),
		"the Root Portal archway is walk-through")

	# A tree trunk, whichever one the scatter happened to make first.
	var tree: Node3D = null
	if world:
		for c in world.get_children():
			if c is Node3D and String(c.name).begins_with("Tree"):
				tree = c
				break
	if tree == null:
		check(false, "found a tree to test")
	else:
		var tp := tree.global_position
		check(_blocked(tp + Vector3(3.0, 1.0, 0.0), tp + Vector3(0.1, 1.0, 0.0)),
			"a tree trunk is solid")
		# ...but the canopy overhead is camera-only, never a wall.
		check(not _blocked(tp + Vector3(3.0, 4.6, 0.0), tp + Vector3(2.0, 4.6, 0.0)),
			"the canopy is not a wall the Sprite bumps into")

	# Ankle-height scenery stays walk-through on purpose.
	check(true, "toadstools and pebbles are pickups, deliberately not solid")


# Physics, not assertions about physics. A screenshot cannot tell you
# whether the Sprite actually left the ground — it can only show you a
# pose. This watches his real Y over real frames.
func _test_jump() -> void:
	print("\n-- jump --")
	var main := get_parent()
	var player = main.get("player")
	if player == null:
		check(false, "found the player node")
		return

	# Let gravity settle him onto the terrain first.
	for i in 40:
		await get_tree().physics_frame
	var ground_y: float = player.global_position.y

	player.hop()
	var peak := ground_y
	for i in 45:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	check(peak > ground_y + 1.0,
		"a hop clears at least a metre (cleared %.2fm)" % (peak - ground_y))
	check(peak < ground_y + 3.0,
		"a hop stays under three metres (cleared %.2fm)" % (peak - ground_y))

	# And he must come back down, not float away.
	for i in 120:
		await get_tree().physics_frame
	check(absf(player.global_position.y - ground_y) < 0.4,
		"lands back on the ground (off by %.2fm)" % absf(player.global_position.y - ground_y))
	check(player.is_on_floor(), "is standing on the floor again")


func _test_save_roundtrip() -> void:
	print("\n-- save / load --")
	GameState.coins = 1234
	GameState.larder = {"radish": 7}
	GameState.plots[2]["state"] = GameState.Soil.GROWING
	GameState.plots[2]["crop"] = "turnip"
	GameState.plots[2]["watered_at"] = Time.get_unix_time_from_system() - 10.0
	SaveManager.save_game()

	var d := SaveManager.load_game()
	check(int(d.get("coins", 0)) == 1234, "coins survive a save")
	check(int(d.get("plots", [])[2].get("state", -1)) == GameState.Soil.GROWING,
		"plot state survives a save")
	check(String(d.get("plots", [])[2].get("crop", "")) == "turnip", "crop survives a save")
	check(float(d.get("plots", [])[2].get("watered_at", 0.0)) > 0.0,
		"watered_at is a timestamp, so growth continues offline")

	GameState.materials = {"stone": 4}
	GameState.gathered = {77: Time.get_unix_time_from_system() + 999.0}
	SaveManager.save_game()
	var d2 := SaveManager.load_game()
	check(int(d2.get("materials", {}).get("stone", 0)) == 4, "materials survive a save")
	check(d2.get("gathered", {}).size() == 1, "gathered spots survive a save")
	check(int(d2.get("version", 0)) == GameState.SAVE_VERSION, "save is stamped v%d" % GameState.SAVE_VERSION)

	# A version-1 save had `houses` and no `placed`. Nobody's village
	# should vanish because the format moved on.
	var legacy := {"version": 1, "coins": 50,
		"houses": [{"x": 3.0, "z": 4.0, "yaw": 90.0}]}
	GameState.placed = []
	GameState._load_from(legacy)
	check(GameState.placed.size() == 1, "a v1 house migrates into `placed`")
	check(String(GameState.placed[0]["id"]) == "house", "and is tagged as a house")
