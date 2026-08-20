# =============================================================
# save_manager.gd — AUTOLOAD "SaveManager"
# -------------------------------------------------------------
# GODOT CONCEPT — AUTOLOADS:
# An autoload is a script Godot loads once at startup and keeps
# alive for the whole session, reachable from anywhere by name
# (e.g. SaveManager.save_game()). They're registered in
# Project Settings > Globals > Autoload (already done for you in
# project.godot). Think of them like app-wide services.
#
# WHAT THIS ONE DOES:
# Reads/writes the save file as JSON at user://tendril_hills_3d.json
# "user://" is Godot's per-app writable folder. On iOS it maps to
# the app's Documents directory, which iCloud-backs up automatically.
#
# OFFLINE GROWTH:
# We save Unix timestamps (planted_at) rather than "seconds left",
# so crops keep "growing" while the app is closed — on next launch
# the elapsed real time is simply recomputed. Same trick the HTML
# prototype and the Roblox TDD use.
# =============================================================
extends Node

const SAVE_PATH := "user://tendril_hills_3d.json"

var _dirty := false
var _autosave_timer: Timer


func _ready() -> void:
	# Autosave every 30 seconds if anything changed
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 30.0
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(func():
		if _dirty:
			save_game()
	)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	# iOS/Android: the OS can kill a backgrounded app at any time,
	# so we save the moment we're paused or closed.
	if what == NOTIFICATION_APPLICATION_PAUSED \
	or what == NOTIFICATION_WM_CLOSE_REQUEST \
	or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()


func mark_dirty() -> void:
	_dirty = true


func save_game() -> void:
	# GameState may not exist yet during very early startup
	if not is_instance_valid(GameState):
		return
	var data: Dictionary = GameState.to_save_dict()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not open save file for writing: %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	_dirty = false


func load_game() -> Dictionary:
	# Returns {} if there is no valid save.
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file was corrupt — starting fresh.")
		return {}
	return parsed


func wipe() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_dirty = false
