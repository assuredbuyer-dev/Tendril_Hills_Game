# =============================================================
# game_state.gd — AUTOLOAD "GameState"  ★ THE GAME ★
# -------------------------------------------------------------
# Every rule in Tendril Hills lives here: coins, hunger, soil,
# growth, quests, onboarding. Nothing else is allowed to change
# these values directly — the world and the HUD call methods on
# this node and listen to its signals.
#
# This is the same "server is authority" split the Roblox TDD
# used, and it is why the game can be re-skinned, ported, or have
# its whole art layer replaced without touching the rules.
#
# OFFLINE GROWTH: crops store the unix timestamp they were watered
# at, never "seconds remaining", so they keep growing while the
# game is closed.
# =============================================================
extends Node

signal coins_changed(amount: int)
signal hunger_changed(value: float)
signal inventory_changed()
signal plot_changed(index: int)
signal plots_rebuilt()
signal quests_changed()
signal placed_changed()
signal materials_changed()
signal gathered_changed(node_id: int)
signal toast(text: String, color: Color)
signal say(who: String, text: String)
signal portal_unlocked()
signal hunger_band_changed(band: int)

const SAVE_VERSION := 2   # 2 added materials, gathering and crafted placeables

# Soil states
enum Soil { UNTILLED, TILLED, PLANTED, GROWING, READY }

# How full the Sprite is. Drives walk speed and harvest luck -- see
# Defs' hunger block for why this is a bonus band and not a health bar.
enum Belly { PECKISH, FINE, WELL_FED }

# --- Farm layout ---------------------------------------------
const PLOT_COLS := 5
const PLOT_ROWS := 4
const PLOT_SPACING := 2.6

# --- Live state ----------------------------------------------
var coins: int = Defs.STARTING_COINS
var hunger: float = 72.0
var seeds: Dictionary = {}          # crop_id -> count
var larder: Dictionary = {}         # crop_id -> harvested count
var plots: Array = []               # see _blank_plot()
var placed: Array = []              # [{id, x, z, yaw}] — everything you have built
var materials: Dictionary = {}      # material_id -> count in the pouch
var build_bag: Dictionary = {}      # recipe_id -> how many crafted, not yet placed
var gathered: Dictionary = {}       # node_id -> unix time it regrows
var selected_build: String = ""
var stats: Dictionary = {}          # counters the quests read
var quests_done: Array = []
var onboarding_index: int = 0
var portal_open: bool = false
var selected_seed: String = "carrot"

var _hunger_accum: float = 0.0
var _belly_band: int = Belly.FINE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_plot_layout()
	var data := SaveManager.load_game()
	if data.is_empty():
		_new_game()
	else:
		_load_from(data)


func _process(delta: float) -> void:
	# Hunger drain
	_hunger_accum += delta
	var step: float = Defs.HUNGER_DRAIN_SECONDS
	while _hunger_accum >= step:
		_hunger_accum -= step
		if hunger > 0.0:
			hunger = maxf(0.0, hunger - 1.0)
			hunger_changed.emit(hunger)
			_refresh_belly_band()

	# Ripening
	var now := Time.get_unix_time_from_system()
	for i in plots.size():
		var p: Dictionary = plots[i]
		if p["state"] == Soil.GROWING and now - float(p["watered_at"]) >= _plot_grow_time(p):
			p["state"] = Soil.READY
			plot_changed.emit(i)
			SaveManager.mark_dirty()


# =============================================================
#  Setup
# =============================================================

func _blank_plot(x: float, z: float) -> Dictionary:
	return {"x": x, "z": z, "state": Soil.UNTILLED, "crop": "", "watered_at": 0.0,
		"speed": 1.0}


func _build_plot_layout() -> void:
	plots.clear()
	var origin := Terrain.FARM_CENTRE
	var w: float = (PLOT_COLS - 1) * PLOT_SPACING * 0.5
	var d: float = (PLOT_ROWS - 1) * PLOT_SPACING * 0.5
	for r in PLOT_ROWS:
		for c in PLOT_COLS:
			var x: float = origin.x - w + c * PLOT_SPACING
			var z: float = origin.z - d + r * PLOT_SPACING
			plots.append(_blank_plot(x, z))


func _new_game() -> void:
	coins = Defs.STARTING_COINS
	hunger = 72.0
	seeds = Defs.START_SEEDS.duplicate(true)
	larder = {}
	placed = []
	materials = {}
	build_bag = {}
	gathered = {}
	selected_build = ""
	stats = {}
	quests_done = []
	onboarding_index = 0
	portal_open = false
	selected_seed = "carrot"
	# Seed the band from the starting hunger, or the first drain tick
	# announces "Full belly!" to a player who never ate anything.
	_belly_band = belly_band()
	SaveManager.mark_dirty()


func plot_position(index: int) -> Vector3:
	var p: Dictionary = plots[index]
	return Terrain.point(p["x"], p["z"])


# =============================================================
#  What the placeables actually do
# =============================================================

## How fast crops grow at this spot. Scarecrows help; a field of forty
## scarecrows does not help forty times, which is why the bonus caps.
func growth_speed_at(x: float, z: float) -> float:
	var bonus := 0.0
	for item in placed:
		if String(item["id"]) != "scarecrow":
			continue
		var d := Vector2(x - float(item["x"]), z - float(item["z"])).length()
		if d <= Defs.SCARECROW_RADIUS:
			bonus += Defs.SCARECROW_BONUS
	return 1.0 + minf(bonus, Defs.SCARECROW_MAX_BONUS)


## 0..1 — how full a hive is. Like everything else that takes time in
## this game, it is a stored timestamp, so it fills while you are away.
func hive_progress(index: int) -> float:
	if index < 0 or index >= placed.size():
		return 0.0
	if String(placed[index]["id"]) != "hive":
		return 0.0
	var since: float = Time.get_unix_time_from_system() - float(placed[index].get("filled_at", 0.0))
	return clampf(since / Defs.HIVE_SECONDS, 0.0, 1.0)


func collect_hive(index: int) -> bool:
	if hive_progress(index) < 1.0:
		Sfx.play("deny")
		var left := int(ceilf(Defs.HIVE_SECONDS * (1.0 - hive_progress(index))))
		_note("The bees are still working — about %ds" % left, Palette.UI_TEXT_SOFT)
		return false
	larder["honey"] = int(larder.get("honey", 0)) + 1
	placed[index]["filled_at"] = Time.get_unix_time_from_system()
	Sfx.play("coin")
	_bump("honey_taken")
	inventory_changed.emit()
	placed_changed.emit()
	_note("Collected a jar of honey!", Palette.WARM_YELLOW)
	SaveManager.mark_dirty()
	_check_quests()
	return true


func _grow_time(crop: String) -> float:
	if crop == "" or not Defs.CROPS.has(crop):
		return 9999.0
	return float(Defs.CROPS[crop]["grow"])


## Grow time for THIS plot, including any scarecrow help that was
## standing nearby when it was watered. Baked in at watering rather
## than recomputed, so moving a scarecrow never rewinds a crop.
func _plot_grow_time(p: Dictionary) -> float:
	return _grow_time(String(p["crop"])) / maxf(0.25, float(p.get("speed", 1.0)))


## 0..1 ripeness, used by the world to pick a growth stage mesh.
func plot_progress(index: int) -> float:
	var p: Dictionary = plots[index]
	if p["state"] == Soil.READY:
		return 1.0
	if p["state"] != Soil.GROWING:
		return 0.0
	var elapsed: float = Time.get_unix_time_from_system() - float(p["watered_at"])
	return clampf(elapsed / _plot_grow_time(p), 0.0, 1.0)


# =============================================================
#  The one-button farming loop
#  Interacting with a plot always does the obvious next thing.
# =============================================================

func interact_plot(index: int) -> void:
	var p: Dictionary = plots[index]
	match int(p["state"]):
		Soil.UNTILLED:
			p["state"] = Soil.TILLED
			Sfx.play("water")
			_advance_onboarding("till")
			_note("Soil turned over", Palette.EARTH)
		Soil.TILLED:
			if seed_count(selected_seed) <= 0:
				Sfx.play("deny")
				_note("No %s seeds — buy some at the stall" % _crop_name(selected_seed), Palette.UI_WARN)
				return
			seeds[selected_seed] = seed_count(selected_seed) - 1
			p["crop"] = selected_seed
			p["state"] = Soil.PLANTED
			Sfx.play("pop")
			inventory_changed.emit()
			_advance_onboarding("plant")
			_note("Planted a %s seed" % _crop_name(selected_seed), Palette.MOSS)
		Soil.PLANTED:
			p["state"] = Soil.GROWING
			p["watered_at"] = Time.get_unix_time_from_system()
			p["speed"] = growth_speed_at(float(p["x"]), float(p["z"]))
			Sfx.play("water")
			_bump("waters")
			_advance_onboarding("water")
			if float(p["speed"]) > 1.01:
				_note("Watered — the scarecrow is helping this one along",
					Palette.WARM_YELLOW)
			else:
				_note("Watered", Palette.SKY_BLUE)
		Soil.GROWING:
			Sfx.play("deny")
			var left := int(ceilf(_plot_grow_time(p) * (1.0 - plot_progress(index))))
			_note("Still growing — about %ds to go" % left, Palette.UI_TEXT_SOFT)
			return
		Soil.READY:
			var crop: String = p["crop"]
			# A well-fed Sprite sometimes pulls up two. This is the whole
			# reward for keeping the belly bar high -- no penalty anywhere.
			var yield_n := 1
			if belly_band() == Belly.WELL_FED and _rng.randf() < Defs.WELL_FED_BONUS_CHANCE:
				yield_n = 2
			larder[crop] = int(larder.get(crop, 0)) + yield_n
			p["state"] = Soil.UNTILLED
			p["crop"] = ""
			p["watered_at"] = 0.0
			Sfx.play("pop")
			for _n in yield_n:
				_bump("%s_harvested" % crop)
				_bump("harvests")
			inventory_changed.emit()
			_advance_onboarding("harvest")
			if yield_n > 1:
				_note("Two %ss! A full belly pays." % _crop_name(crop).to_lower(), Palette.WARM_YELLOW)
			else:
				_note("Harvested a %s!" % _crop_name(crop), Palette.CARROT)
	plot_changed.emit(index)
	SaveManager.mark_dirty()
	_check_quests()


# =============================================================
#  Belly bands -- what a full stomach is actually FOR
# =============================================================

func belly_band() -> int:
	if hunger >= Defs.HUNGER_WELL_FED:
		return Belly.WELL_FED
	if hunger <= Defs.HUNGER_PECKISH:
		return Belly.PECKISH
	return Belly.FINE


## Walk speed multiplier. Player reads this every physics frame.
func speed_multiplier() -> float:
	match belly_band():
		Belly.WELL_FED: return Defs.SPEED_WELL_FED
		Belly.PECKISH:  return Defs.SPEED_PECKISH
	return 1.0


func _refresh_belly_band() -> void:
	var band := belly_band()
	if band == _belly_band:
		return
	var was := _belly_band
	_belly_band = band
	hunger_band_changed.emit(band)
	# Announce it only on the way in, and only in the player's language.
	if band == Belly.WELL_FED:
		_note("Full belly! Light on your feet.", Palette.MOSS)
	elif band == Belly.PECKISH:
		_note("Getting peckish... press 1 to eat", Palette.UI_WARN)
	elif was == Belly.PECKISH:
		_note("That is better.", Palette.MOSS)


# =============================================================
#  Inventory actions
# =============================================================

func seed_count(crop: String) -> int:
	return int(seeds.get(crop, 0))


func larder_count(crop: String) -> int:
	return int(larder.get(crop, 0))


func total_larder() -> int:
	var n := 0
	for k in larder:
		n += int(larder[k])
	return n


func eat_something() -> void:
	# Eats the most filling thing you have.
	var best := ""
	var best_hunger := -1
	for crop in larder:
		if int(larder[crop]) <= 0:
			continue
		var h: int = int(Defs.CROPS[crop]["hunger"])
		if h > best_hunger:
			best_hunger = h
			best = crop
	if best == "":
		Sfx.play("deny")
		_note("Nothing to eat — grow something first", Palette.UI_WARN)
		return
	if hunger >= 99.5:
		Sfx.play("deny")
		_note("Too full!", Palette.UI_TEXT_SOFT)
		return
	larder[best] = int(larder[best]) - 1
	hunger = minf(100.0, hunger + float(best_hunger))
	_refresh_belly_band()
	Sfx.play("munch")
	_bump("meals")
	hunger_changed.emit(hunger)
	inventory_changed.emit()
	_advance_onboarding("eat")
	_note("Ate a %s  +%d" % [_crop_name(best), best_hunger], Palette.MOSS)
	SaveManager.mark_dirty()
	_check_quests()


func cycle_seed() -> void:
	var ids: Array = Defs.plantable_crops()
	var i: int = ids.find(selected_seed)
	selected_seed = ids[(i + 1) % ids.size()]
	Sfx.play("pop")
	inventory_changed.emit()
	_note("Selected %s seeds" % _crop_name(selected_seed), Palette.MOSS)


func buy_seed(crop: String) -> void:
	var cost: int = int(Defs.CROPS[crop]["seed_cost"])
	if coins < cost:
		Sfx.play("deny")
		_note("Not enough coins", Palette.UI_WARN)
		return
	coins -= cost
	seeds[crop] = seed_count(crop) + 1
	selected_seed = crop
	Sfx.play("coin")
	coins_changed.emit(coins)
	inventory_changed.emit()
	_note("Bought a %s seed" % _crop_name(crop), Palette.MOSS)
	SaveManager.mark_dirty()


func sell_larder() -> void:
	var earned := 0
	for crop in larder.keys():
		var n: int = int(larder[crop])
		if n <= 0:
			continue
		earned += n * int(Defs.CROPS[crop]["coins"])
		larder[crop] = 0
	if earned <= 0:
		Sfx.play("deny")
		_note("Nothing in your basket to sell", Palette.UI_TEXT_SOFT)
		return
	coins += earned
	Sfx.play("coin")
	coins_changed.emit(coins)
	inventory_changed.emit()
	_note("Sold your basket  +%d coins" % earned, Palette.WARM_YELLOW)
	SaveManager.mark_dirty()


# =============================================================
#  Gathering
#  Toadstools, stones and fallen branches. Pick up, walk on, regrow.
# =============================================================

func material_count(id: String) -> int:
	return int(materials.get(id, 0))


## Is this world node currently picked (and not yet regrown)?
func is_gathered(node_id: int) -> bool:
	if not gathered.has(node_id):
		return false
	if Time.get_unix_time_from_system() >= float(gathered[node_id]):
		gathered.erase(node_id)          # regrown while we were away
		return false
	return true


func gather(node_id: int, material: String) -> bool:
	if is_gathered(node_id):
		return false
	materials[material] = material_count(material) + 1
	gathered[node_id] = Time.get_unix_time_from_system() + Defs.GATHER_RESPAWN_SECONDS
	Sfx.play("pop")
	_bump("gathered")
	materials_changed.emit()
	gathered_changed.emit(node_id)
	_note("Picked up a %s" % String(Defs.MATERIALS[material]["name"]), Palette.MOSS)
	SaveManager.mark_dirty()
	_check_quests()
	return true


## Anything that has regrown since the last check, so the world can
## put it back. Called on a slow timer — this is scenery, not physics.
func take_regrown() -> Array:
	var now := Time.get_unix_time_from_system()
	var back: Array = []
	for id in gathered.keys():
		if now >= float(gathered[id]):
			back.append(id)
	for id in back:
		gathered.erase(id)
	if back.size() > 0:
		SaveManager.mark_dirty()
	return back


# =============================================================
#  Crafting
# =============================================================

func can_craft(recipe_id: String) -> bool:
	if not Defs.RECIPES.has(recipe_id):
		return false
	for mat in Defs.RECIPES[recipe_id]["cost"]:
		if material_count(mat) < int(Defs.RECIPES[recipe_id]["cost"][mat]):
			return false
	return true


func missing_for(recipe_id: String) -> String:
	var short: Array = []
	for mat in Defs.RECIPES[recipe_id]["cost"]:
		var need: int = int(Defs.RECIPES[recipe_id]["cost"][mat]) - material_count(mat)
		if need > 0:
			short.append("%d %s" % [need, String(Defs.MATERIALS[mat]["name"]).to_lower()])
	return ", ".join(short)


func craft(recipe_id: String) -> bool:
	if not Defs.RECIPES.has(recipe_id):
		return false
	if not can_craft(recipe_id):
		Sfx.play("deny")
		_note("Still need %s" % missing_for(recipe_id), Palette.UI_WARN)
		return false
	for mat in Defs.RECIPES[recipe_id]["cost"]:
		materials[mat] = material_count(mat) - int(Defs.RECIPES[recipe_id]["cost"][mat])
	build_bag[recipe_id] = bag_count(recipe_id) + 1
	if selected_build == "":
		selected_build = recipe_id
	Sfx.play("chime")
	_bump("crafted")
	materials_changed.emit()
	_note("Crafted a %s — press 3 to place it" % String(Defs.RECIPES[recipe_id]["name"]),
		Palette.WARM_YELLOW)
	SaveManager.mark_dirty()
	_check_quests()
	return true


func bag_count(recipe_id: String) -> int:
	return int(build_bag.get(recipe_id, 0))


func total_in_bag() -> int:
	var n := 0
	for k in build_bag:
		n += int(build_bag[k])
	return n


## Recipe ids you own at least one of, in RECIPES order.
func placeable_ids() -> Array:
	var out: Array = []
	for id in Defs.RECIPES:
		if bag_count(id) > 0:
			out.append(id)
	return out


## Move to the next thing you are holding. Returns false if empty-handed.
func cycle_build() -> bool:
	var ids := placeable_ids()
	if ids.is_empty():
		selected_build = ""
		return false
	var i: int = ids.find(selected_build)
	selected_build = ids[(i + 1) % ids.size()] if i >= 0 else ids[0]
	return true


# =============================================================
#  Placing what you crafted
# =============================================================

## Why a placement is refused, or "" if it is fine. Returning the
## reason rather than a bool is what lets the HUD say something useful
## instead of just buzzing at a seven-year-old.
func placement_problem(recipe_id: String, x: float, z: float,
		player_pos: Vector3 = Vector3.INF) -> String:
	var clearance := Defs.clearance(recipe_id)
	if not Terrain.is_buildable(x, z):
		return "Too steep, or too close to the farm"
	# Never let the player seal themselves inside something solid.
	if player_pos != Vector3.INF:
		var from_player := Vector2(x - player_pos.x, z - player_pos.z).length()
		if from_player < clearance * 0.75:
			return "Stand back a little"
	for other in placed:
		var gap: float = clearance + Defs.clearance(String(other["id"]))
		if Vector2(x - float(other["x"]), z - float(other["z"])).length() < gap * 0.6:
			return "Too close to what you already built"
	return ""


func place_build(recipe_id: String, x: float, z: float, yaw: float,
		player_pos: Vector3 = Vector3.INF) -> bool:
	if bag_count(recipe_id) <= 0:
		Sfx.play("deny")
		_note("Craft one at the workbench first", Palette.UI_WARN)
		return false
	var problem := placement_problem(recipe_id, x, z, player_pos)
	if problem != "":
		Sfx.play("deny")
		_note(problem, Palette.UI_WARN)
		return false

	build_bag[recipe_id] = bag_count(recipe_id) - 1
	if bag_count(recipe_id) <= 0:
		build_bag.erase(recipe_id)
		cycle_build()
	var entry := {"id": recipe_id, "x": x, "z": z, "yaw": yaw}
	if recipe_id == "hive":
		entry["filled_at"] = Time.get_unix_time_from_system()
	placed.append(entry)
	if recipe_id == "scarecrow":
		_bump("scarecrows")
	Sfx.play("chime")
	placed_changed.emit()
	materials_changed.emit()
	if recipe_id == "house":
		_bump("houses")
		_note("A new home in Tendril Hills!", Palette.DEEP_RED)
	else:
		_note("Placed a %s" % String(Defs.RECIPES[recipe_id]["name"]), Palette.MOSS)
	SaveManager.mark_dirty()
	_check_quests()
	return true


# =============================================================
#  Quests, onboarding, portal
# =============================================================

func _bump(key: String, by: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + by


func active_quests() -> Array:
	var out: Array = []
	for q in Defs.QUESTS:
		if q["id"] in quests_done:
			continue
		out.append(q)
		if out.size() >= 3:
			break
	return out


func quest_progress(q: Dictionary) -> int:
	return mini(int(stats.get(q["key"], 0)), int(q["target"]))


func _check_quests() -> void:
	var changed := false
	for q in Defs.QUESTS:
		if q["id"] in quests_done:
			continue
		if int(stats.get(q["key"], 0)) >= int(q["target"]):
			quests_done.append(q["id"])
			coins += int(q["reward"])
			coins_changed.emit(coins)
			Sfx.play("chime")
			_note("Quest complete — %s  +%d coins" % [q["text"], q["reward"]], Palette.WARM_YELLOW)
			changed = true
	if changed:
		quests_changed.emit()
		SaveManager.mark_dirty()
		if not portal_open and quests_done.size() >= Defs.PORTAL_QUESTS_REQUIRED:
			portal_open = true
			Sfx.play("portal")
			portal_unlocked.emit()
			say.emit("Old Sprout", "The roots are parting... Tendril Valley is waking up. That's a story for the next update, little sprite.")


func onboarding_step() -> Dictionary:
	if onboarding_index >= Defs.ONBOARDING.size():
		return {}
	return Defs.ONBOARDING[onboarding_index]


func _advance_onboarding(after_id: String) -> void:
	var step := onboarding_step()
	if step.is_empty():
		return
	if step["id"] == after_id:
		onboarding_index += 1
		_emit_onboarding()


func advance_onboarding_manually() -> void:
	if onboarding_index < Defs.ONBOARDING.size():
		onboarding_index += 1
		_emit_onboarding()


func _emit_onboarding() -> void:
	var step := onboarding_step()
	SaveManager.mark_dirty()
	if step.is_empty():
		return
	if String(step["who"]) != "" or String(step["text"]) != "":
		say.emit(String(step["who"]), String(step["text"]))


func _note(text: String, color: Color) -> void:
	toast.emit(text, color)


func _crop_name(crop: String) -> String:
	if Defs.CROPS.has(crop):
		return String(Defs.CROPS[crop]["name"])
	return crop


# =============================================================
#  Save / load
# =============================================================

func to_save_dict() -> Dictionary:
	var plot_data: Array = []
	for p in plots:
		plot_data.append({
			"state": int(p["state"]),
			"crop": String(p["crop"]),
			"watered_at": float(p["watered_at"]),
			"speed": float(p.get("speed", 1.0)),
		})
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"hunger": hunger,
		"seeds": seeds,
		"larder": larder,
		"plots": plot_data,
		"placed": placed,
		"materials": materials,
		"build_bag": build_bag,
		"gathered": gathered,
		"selected_build": selected_build,
		"stats": stats,
		"quests_done": quests_done,
		"onboarding_index": onboarding_index,
		"portal_open": portal_open,
		"selected_seed": selected_seed,
		"left_at": Time.get_unix_time_from_system(),
	}


func _load_from(d: Dictionary) -> void:
	coins = int(d.get("coins", Defs.STARTING_COINS))
	hunger = float(d.get("hunger", 72.0))
	seeds = d.get("seeds", Defs.START_SEEDS.duplicate(true))
	larder = d.get("larder", {})
	placed = d.get("placed", [])
	materials = d.get("materials", {})
	build_bag = d.get("build_bag", {})
	selected_build = String(d.get("selected_build", ""))

	# JSON has no integer keys — every key comes back a string. Put the
	# gathered-node ids back to ints or is_gathered() silently misses
	# every one of them and the meadow looks untouched.
	gathered = {}
	for k in d.get("gathered", {}):
		gathered[int(k)] = float(d["gathered"][k])

	# --- v1 -> v2 migration -------------------------------------
	# v1 stored a bare `houses` list and bought houses with coins.
	# v2 stores everything you build in one `placed` list with a
	# recipe id. Carry the old houses across rather than deleting
	# somebody's village.
	if int(d.get("version", 1)) < 2:
		for h in d.get("houses", []):
			placed.append({"id": "house", "x": float(h["x"]), "z": float(h["z"]),
				"yaw": float(h.get("yaw", 0.0))})
		if placed.size() > 0:
			_note("Your houses are still standing.", Palette.MOSS)
	stats = d.get("stats", {})
	quests_done = d.get("quests_done", [])
	onboarding_index = int(d.get("onboarding_index", 0))
	portal_open = bool(d.get("portal_open", false))
	selected_seed = String(d.get("selected_seed", "carrot"))

	var saved: Array = d.get("plots", [])
	for i in mini(saved.size(), plots.size()):
		var s: Dictionary = saved[i]
		plots[i]["state"] = int(s.get("state", Soil.UNTILLED))
		plots[i]["crop"] = String(s.get("crop", ""))
		plots[i]["watered_at"] = float(s.get("watered_at", 0.0))
		plots[i]["speed"] = float(s.get("speed", 1.0))

	# Hunger keeps ticking while away, but gently — nobody wants to
	# come back to a starving sprite. Cap the away-drain at 25.
	var away: float = Time.get_unix_time_from_system() - float(d.get("left_at", Time.get_unix_time_from_system()))
	if away > 0.0:
		hunger = maxf(0.0, hunger - minf(25.0, away / (Defs.HUNGER_DRAIN_SECONDS * 4.0)))
	_belly_band = belly_band()
	plots_rebuilt.emit()


func wipe_and_restart() -> void:
	SaveManager.wipe()
	_build_plot_layout()
	_new_game()
	plots_rebuilt.emit()
	placed_changed.emit()
	materials_changed.emit()
	coins_changed.emit(coins)
	hunger_changed.emit(hunger)
	inventory_changed.emit()
	quests_changed.emit()
	_note("Fresh save — starting over", Palette.UI_TEXT_SOFT)
