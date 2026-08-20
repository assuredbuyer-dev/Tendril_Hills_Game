# =============================================================
# main.gd — entry point. Assembles the three layers and wires
# them together, then gets out of the way.
#
#   World  — the diorama (display)
#   Player — the Sprite you steer (input)
#   Hud    — the clay interface (display)
#
# GameState (autoload) holds every rule. None of these three
# talk to each other except through it and through the handful
# of signals connected below.
# =============================================================
extends Node3D

var world: World
var player: Player
var hud: Hud


func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)

	player = Player.new()
	player.name = "Player"
	player.world = world
	player.position = Terrain.point(Terrain.SPAWN_POS.x, Terrain.SPAWN_POS.z) + Vector3(0, 0.6, 0)
	add_child(player)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)

	player.target_changed.connect(_on_target_changed)
	player.wants_shop.connect(func(): hud.toggle_shop())
	player.wants_bench.connect(func(): hud.toggle_craft())
	player.wants_quests.connect(_read_quest_board)
	player.build_mode_changed.connect(func(active): hud.set_build_prompt(active))

	get_window().title = "Tendril Hills — Tendrel Studios"

	# Dev self-test (see scenes/dev/selftest.gd). Off unless asked.
	if "--selftest" in OS.get_cmdline_user_args():
		var st: Node = load("res://scenes/dev/selftest.gd").new()
		add_child(st)
		st.run()
		return

	# Dev screenshot harness (see scenes/dev/capture.gd). Off unless asked.
	if "--shots" in OS.get_cmdline_user_args():
		var cap: Node = load("res://scenes/dev/capture.gd").new()
		add_child(cap)
		cap.setup(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		hud.toggle_help()


func _on_target_changed(text: String, _kind: String) -> void:
	hud.set_prompt(text)


func _read_quest_board() -> void:
	var active := GameState.active_quests()
	if active.is_empty():
		GameState.say.emit("Quest Board", "Every scroll is signed off. Tendril Hills is well tended.")
		return
	var q: Dictionary = active[0]
	GameState.say.emit("Quest Board", "%s — %d of %d done. Reward: %d coins." % [
		q["text"], GameState.quest_progress(q), int(q["target"]), int(q["reward"])])
