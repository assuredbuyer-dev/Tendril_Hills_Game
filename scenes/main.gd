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
var lobby: Lobby
var touch: TouchControls


## True for the headless harnesses, which must never see a menu.
func _is_dev_run() -> bool:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--nettest="):
			return true
	return "--selftest" in args or "--shots" in args or "--bench" in args


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

	# A thumbstick and buttons, but only on a device that needs them.
	# See Controls.wants_touch_ui -- a MacBook never gets these.
	if Controls.wants_touch_ui():
		touch = TouchControls.new()
		touch.name = "Touch"
		add_child(touch)

	player.target_changed.connect(_on_target_changed)
	player.wants_shop.connect(func(): hud.toggle_shop())
	player.wants_bench.connect(func(): hud.toggle_craft())
	player.wants_quests.connect(_read_quest_board)
	player.build_mode_changed.connect(func(active): hud.set_build_prompt(active))

	get_window().title = "Tendril Hills — Tendrel Studios"

	# The lobby covers everything until somebody picks solo, host or
	# join. The world is already built and ticking behind it, which is
	# why joining is instant -- there is nothing left to load.
	#
	# Skipped entirely for --selftest, --shots and --bench: a dev tool
	# that stops at a name box is a dev tool nobody runs.
	if not _is_dev_run():
		lobby = Lobby.new()
		lobby.name = "Lobby"
		add_child(lobby)
		lobby.ready_to_play.connect(_on_lobby_done)
		# Both, deliberately: the Sprite reads movement in
		# _physics_process and everything else in _unhandled_input,
		# so switching off one still leaves it half awake behind the
		# menu -- you would press E to type your name and till a plot.
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)

	# Dev self-test (see scenes/dev/selftest.gd). Off unless asked.
	if "--selftest" in OS.get_cmdline_user_args():
		var st: Node = load("res://scenes/dev/selftest.gd").new()
		add_child(st)
		st.run()
		return

	# Two-machine network test (see scenes/dev/nettest.gd).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nettest="):
			var nt: Node = load("res://scenes/dev/nettest.gd").new()
			add_child(nt)
			nt.run(arg.substr(10))
			return

	# Dev benchmark (see scenes/dev/bench.gd). Off unless asked.
	if "--bench" in OS.get_cmdline_user_args():
		var bn: Node = load("res://scenes/dev/bench.gd").new()
		add_child(bn)
		bn.setup(self)
		return

	# Dev screenshot harness (see scenes/dev/capture.gd). Off unless asked.
	if "--shots" in OS.get_cmdline_user_args():
		var cap: Node = load("res://scenes/dev/capture.gd").new()
		add_child(cap)
		cap.setup(self)


func _on_lobby_done() -> void:
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	# Drop the new arrival at their own clearing if they have one, so
	# four kids do not all spawn on top of each other in the meadow.
	var mine := GameState.my_homestead()
	if mine >= 0:
		var c: Vector3 = Terrain.HOMESTEADS[mine]["pos"]
		player.global_position = Terrain.point(c.x, c.z + 4.0) + Vector3(0, 0.6, 0)
		player.snap_camera()


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
