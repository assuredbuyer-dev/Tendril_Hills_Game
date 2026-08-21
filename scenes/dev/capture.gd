# =============================================================
# capture.gd — dev tool: drive the game and save screenshots.
# -------------------------------------------------------------
# Run:  ./tools/shots.sh          (see docs/LOOP.md)
# Raw:  godot --path . --rendering-driver opengl3 -- --shots
#       (note the bare `--` — everything after it is OUR args, not
#        Godot's. Without it Godot eats the flag and nothing happens.)
#
# Writes PNGs into the project folder at .shots/ so Claude can read
# them straight from the repo, then quits. Override the destination
# with  -- --shots --out=res://somewhere  or an absolute path.
#
# Not loaded unless --shots is passed, so it costs the shipped
# game nothing.
# =============================================================
extends Node

const DEFAULT_OUT := "res://.shots"

var _shots: Array = []
var _main: Node3D


var _out: String = DEFAULT_OUT


func setup(main: Node3D) -> void:
	_main = main
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_shots = [
		{"name": "01_spawn",     "pos": Vector3(0, 0, 12.0),   "yaw": 0.0,   "wait": 1.2},
		{"name": "02_village",   "pos": Vector3(2.0, 0, 5.0),  "yaw": 0.5,   "wait": 0.6},
		{"name": "03_stall",     "pos": Vector3(5.0, 0, 4.6),  "yaw": 0.2,   "wait": 0.6},
		{"name": "04_farm",      "pos": Vector3(13.5, 0, 1.0), "yaw": -1.2,  "wait": 0.6},
		{"name": "05_farm_close","pos": Vector3(15.6, 0, 1.0), "yaw": -1.4,  "wait": 0.6},
		{"name": "06_portal",    "pos": Vector3(-14.0, 0, -2.0),"yaw": 1.5,  "wait": 0.6},
		{"name": "07_hills",     "pos": Vector3(-6.0, 0, -14.0),"yaw": 2.6,  "wait": 0.6},
		{"name": "08_sprout",    "pos": Vector3(1.4, 0, 11.6), "yaw": 0.0,   "wait": 0.6},
		# Caught mid-hop, to check the airborne pose and the stretch.
		{"name": "09_jump",      "pos": Vector3(-2.0, 0, 6.5), "yaw": 0.3,
		 "wait": 0.30, "hop": true},
		# The workbench, and the pouch/held rows in the HUD beside it.
		{"name": "11_bench",     "pos": Vector3(5.0, 0, 0.4),  "yaw": 3.1,  "wait": 0.6},
		# The new craftables, standing in the world.
		{"name": "12_crafts",    "pos": Vector3(1.0, 0, 10.4), "yaw": 0.15, "wait": 0.6},
		{"name": "13_scarecrow", "pos": Vector3(11.0, 0, 5.4), "yaw": -0.5, "wait": 0.6},
		# Nose-to-cap on a toadstool, to check the spots read.
		{"name": "10_toadstool", "pos": Vector3(7.5, 0, 7.5),  "yaw": 0.9,  "wait": 0.6},

		# --- the bigger map ---------------------------------------
		# The long view. This is the shot that tells you whether the
		# world reads as big or just as empty, and whether distant
		# trees pop in (see World._fade). Look at the horizon, not
		# at the Sprite.
		{"name": "20_long_view", "bare": true,  "pos": Vector3(0, 0, 26.0),   "yaw": 3.14, "wait": 0.8},
		{"name": "21_long_view_e", "bare": true,"pos": Vector3(-24.0, 0, 0),  "yaw": -1.57,"wait": 0.8},
		# A homestead, arriving from the village — the angle a player
		# actually approaches from.
		{"name": "22_homestead", "bare": true,  "pos": Vector3(-26.0, 0, -26.0), "yaw": -2.36, "wait": 0.8},
		# Standing in the middle of one, which is what it looks like
		# when it is yours and still empty.
		{"name": "23_homestead_in", "bare": true,"pos": Vector3(32.0, 0, 32.0), "yaw": 0.8,  "wait": 0.8},
		# Face-on to a signpost, from the village side, to check the
		# name is legible and pointed the right way.
		{"name": "28_sign", "bare": true, "pos": Vector3(30.0, 0, 30.0), "yaw": 0.785, "wait": 0.8},
		# The pockets. Each should read as somewhere before you know
		# what it gives you.
		{"name": "24_stonefall", "bare": true,  "pos": Vector3(0, 0, -40.0),   "yaw": 3.14, "wait": 0.8},
		{"name": "25_grove", "bare": true,      "pos": Vector3(40.0, 0, 0),    "yaw": -1.57,"wait": 0.8},
		{"name": "26_toadfen", "bare": true,    "pos": Vector3(0, 0, 40.0),    "yaw": 0.0,  "wait": 0.8},
		# The rim, to check the bowl edge still reads at the new size.
		{"name": "27_rim", "bare": true,        "pos": Vector3(-40.0, 0, 40.0),"yaw": -0.8, "wait": 0.8},
	]
	_run()


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	# Seed some state so the farm has something to look at.
	_seed_demo_state()
	await get_tree().create_timer(0.5).timeout

	for shot in _shots:
		_main.player.global_position = Terrain.point(shot["pos"].x, shot["pos"].z) + Vector3(0, 0.4, 0)
		_main.player.set("_cam_yaw", float(shot["yaw"]))
		# Turn the Sprite three-quarters toward the lens. In play you
		# mostly see his back, but a photograph is for judging the
		# character, and you cannot judge a face you cannot see.
		_main.player.set_facing(float(shot["yaw"]) + PI - 0.6)
		_main.player.snap_camera()
		# Two physics frames so the spring arm resolves its collision
		# before we photograph it, or the first frame shows the lens
		# still buried in whatever it is about to push out of.
		await get_tree().physics_frame
		await get_tree().physics_frame
		# Landscape shots turn the HUD off. Two thirds of the screen is
		# interface, and you cannot judge a horizon you cannot see.
		_main.hud.visible = not bool(shot.get("bare", false))
		if bool(shot.get("hop", false)):
			_main.player.hop()
		await get_tree().create_timer(float(shot["wait"])).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_out, shot["name"]])
		print("[capture] ", shot["name"])
	print("[capture] done -> ", ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _seed_demo_state() -> void:
	# A farm mid-season: some grass, some tilled, some growing, some ripe.
	var now := Time.get_unix_time_from_system()
	var crops := ["carrot", "radish", "turnip"]
	for i in GameState.plots.size():
		var p: Dictionary = GameState.plots[i]
		match i % 5:
			0:
				p["state"] = GameState.Soil.UNTILLED
			1:
				p["state"] = GameState.Soil.TILLED
			2:
				p["state"] = GameState.Soil.GROWING
				p["crop"] = crops[i % 3]
				p["watered_at"] = now - 5.0
			3:
				p["state"] = GameState.Soil.GROWING
				p["crop"] = crops[i % 3]
				p["watered_at"] = now - float(Defs.CROPS[crops[i % 3]]["grow"]) * 0.7
			4:
				p["state"] = GameState.Soil.READY
				p["crop"] = crops[i % 3]
	GameState.coins = 340
	GameState.larder = {"carrot": 4, "radish": 2}
	GameState.stats = {"waters": 5, "carrot_harvested": 3, "meals": 1}
	GameState.materials = {"toadstool": 7, "stone": 4, "branch": 5}
	GameState.build_bag = {"lantern": 1, "fence": 3, "planter": 2}
	GameState.selected_build = "lantern"
	GameState.placed = [
		{"id": "house", "x": -3.0, "z": -4.5, "yaw": 25.0},
		{"id": "house", "x": 3.6, "z": -5.6, "yaw": -40.0},
		{"id": "house", "x": -7.5, "z": 1.2, "yaw": 100.0},
		{"id": "lantern", "x": -1.2, "z": 7.6, "yaw": 0.0},
		{"id": "fence", "x": -4.4, "z": 7.2, "yaw": 0.0},
		{"id": "fence", "x": -3.2, "z": 7.4, "yaw": 0.0},
		{"id": "scarecrow", "x": 11.5, "z": 1.0, "yaw": 200.0},
		{"id": "hive", "x": 9.6, "z": 6.2, "yaw": 0.0,
		 "filled_at": Time.get_unix_time_from_system() - 9999.0},
		{"id": "planter", "x": 2.4, "z": 8.4, "yaw": 0.0},
		{"id": "planter", "x": 3.6, "z": 7.6, "yaw": 40.0},
		{"id": "sign", "x": -2.6, "z": 9.2, "yaw": -20.0},
	]
	GameState.plots_rebuilt.emit()
	GameState.placed_changed.emit()
	GameState.materials_changed.emit()
	GameState.coins_changed.emit(GameState.coins)
	GameState.inventory_changed.emit()
	GameState.quests_changed.emit()
