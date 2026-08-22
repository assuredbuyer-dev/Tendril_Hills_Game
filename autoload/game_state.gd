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

const SAVE_VERSION := 3   # 3 added homestead ownership (multiplayer)

# Soil states
enum Soil { UNTILLED, TILLED, PLANTED, GROWING, READY }

# How full the Sprite is. Drives walk speed and harvest luck -- see
# Defs' hunger block for why this is a bonus band and not a health bar.
enum Belly { PECKISH, FINE, WELL_FED }

# --- Farm layout ---------------------------------------------
const PLOT_COLS := 5
const PLOT_ROWS := 4
const PLOT_SPACING := 2.6
# Each homestead gets a smaller patch than the shared farm. The
# big field to the east is where you learn; your own plot is
# where you commit.
const HOMESTEAD_COLS := 3
const HOMESTEAD_ROWS := 3

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

# --- Shared world state (the host owns these) -----------------
# Which player has claimed each homestead, in Terrain.HOMESTEADS
# order. "" means nobody yet. Stored by NAME rather than by network
# id, because ids are handed out fresh every session and a kid
# expects to walk back into the same clearing tomorrow.
var homestead_owner: Array = []

signal roster_or_claims_changed()

var _hunger_accum: float = 0.0
var _belly_band: int = Belly.FINE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_plot_layout()
	homestead_owner.resize(Terrain.HOMESTEADS.size())
	homestead_owner.fill("")
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
	# The shared farm to the east comes FIRST and keeps indices
	# 0..19 forever. Saves store plots by index, so anything added
	# later has to be added at the end or every existing save
	# wakes up with its carrots in the wrong field.
	_add_plot_grid(Terrain.FARM_CENTRE, PLOT_COLS, PLOT_ROWS)
	# Then one small grid per homestead, in HOMESTEADS order.
	for hs in Terrain.HOMESTEADS:
		_add_plot_grid(hs["farm"], HOMESTEAD_COLS, HOMESTEAD_ROWS)


func _add_plot_grid(origin: Vector3, cols: int, rows: int) -> void:
	var w: float = (cols - 1) * PLOT_SPACING * 0.5
	var d: float = (rows - 1) * PLOT_SPACING * 0.5
	for r in rows:
		for c in cols:
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
	if Net.has_authority():
		var r := _host_hive(index)
		_apply_personal(r)
		return r.has("gain_crop")
	_req_hive.rpc_id(1, index)
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

## What the player presses. In solo play or on the host this runs
## the rules directly; on a client it asks the host and waits.
##
## The split matters: the PLOT is shared world state and only the
## host may change it, but the SEED it costs and the CARROT it
## yields are in the actor's own pockets, which the host cannot see
## and has no business owning. So the actor sends what it has, the
## host decides what happens to the world, and it tells the actor
## what to do to its own basket.
func interact_plot(index: int) -> void:
	var ctx := {
		"seed": selected_seed,
		"seed_n": seed_count(selected_seed),
		"well_fed": belly_band() == Belly.WELL_FED,
	}
	if Net.has_authority():
		_apply_personal(_host_plot_action(index, Net.my_id(), ctx))
	else:
		_req_plot.rpc_id(1, index, ctx)


## Runs on the authority only. Mutates the plot, tells everyone,
## and returns the personal side-effects for whoever asked.
func _host_plot_action(index: int, actor_id: int, ctx: Dictionary) -> Dictionary:
	if index < 0 or index >= plots.size():
		return {}
	var p: Dictionary = plots[index]
	var out := {}
	match int(p["state"]):
		Soil.UNTILLED:
			p["state"] = Soil.TILLED
			out = {"sfx": "water", "note": "Soil turned over",
				"colour": Palette.EARTH, "step": "till"}
		Soil.TILLED:
			var seed_id := String(ctx.get("seed", ""))
			if int(ctx.get("seed_n", 0)) <= 0:
				# Nothing happens to the world, so nothing is broadcast.
				return {"sfx": "deny", "colour": Palette.UI_WARN,
					"note": "No %s seeds — buy some at the stall" % _crop_name(seed_id)}
			p["crop"] = seed_id
			p["state"] = Soil.PLANTED
			out = {"sfx": "pop", "spend_seed": seed_id, "step": "plant",
				"note": "Planted a %s seed" % _crop_name(seed_id),
				"colour": Palette.MOSS}
		Soil.PLANTED:
			p["state"] = Soil.GROWING
			p["watered_at"] = Time.get_unix_time_from_system()
			p["speed"] = growth_speed_at(float(p["x"]), float(p["z"]))
			out = {"sfx": "water", "bump": "waters", "step": "water",
				"note": "Watered", "colour": Palette.SKY_BLUE}
			if float(p["speed"]) > 1.01:
				out["note"] = "Watered — the scarecrow is helping this one along"
				out["colour"] = Palette.WARM_YELLOW
		Soil.GROWING:
			var left := int(ceilf(_plot_grow_time(p) * (1.0 - plot_progress(index))))
			return {"sfx": "deny", "colour": Palette.UI_TEXT_SOFT,
				"note": "Still growing — about %ds to go" % left}
		Soil.READY:
			# The one place ownership bites. Anyone may till, plant and
			# water anywhere -- helping is always allowed -- but the
			# crop belongs to whoever's clearing it grew in.
			if not may_harvest(index, actor_id):
				var owner := owner_of_plot(index)
				return {"sfx": "deny", "colour": Palette.UI_WARN,
					"note": "These are %s's — you can water them, but not pull them up" % owner}
			var crop: String = p["crop"]
			var yield_n := 1
			if bool(ctx.get("well_fed", false)) and _rng.randf() < Defs.WELL_FED_BONUS_CHANCE:
				yield_n = 2
			p["state"] = Soil.UNTILLED
			p["crop"] = ""
			p["watered_at"] = 0.0
			out = {"sfx": "pop", "gain_crop": crop, "gain_n": yield_n,
				"step": "harvest", "colour": Palette.CARROT,
				"note": "Harvested a %s!" % _crop_name(crop)}
			if yield_n > 1:
				out["note"] = "Two %ss! A full belly pays." % _crop_name(crop).to_lower()
				out["colour"] = Palette.WARM_YELLOW
	_broadcast_plot(index)
	plot_changed.emit(index)
	SaveManager.mark_dirty()
	return out


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
	if Net.has_authority():
		var r := _host_gather(node_id, material)
		_apply_personal(r)
		return r.has("gain_material")
	if is_gathered(node_id):
		return false
	_req_gather.rpc_id(1, node_id, material)
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
	# The bag is yours, so this check is yours and happens here on
	# your own machine whether you are host or guest.
	if bag_count(recipe_id) <= 0:
		Sfx.play("deny")
		_note("Craft one at the workbench first", Palette.UI_WARN)
		return false
	if Net.has_authority():
		var r := _host_place(recipe_id, x, z, yaw, Net.my_id(), player_pos)
		_apply_personal(r)
		return r.has("spend_build")
	# A guest checks placement locally too -- not because the host
	# will not check, but so a bad spot says so instantly instead of
	# after a round trip.
	var problem := placement_problem(recipe_id, x, z, player_pos)
	if problem != "":
		Sfx.play("deny")
		_note(problem, Palette.UI_WARN)
		return false
	_req_place.rpc_id(1, recipe_id, x, z, yaw)
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
		"homestead_owner": homestead_owner,
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

	# Who owns which clearing. Sized against the current HOMESTEADS
	# list rather than trusting the file, so adding a fifth homestead
	# does not need a migration.
	var owners: Array = d.get("homestead_owner", [])
	homestead_owner.resize(Terrain.HOMESTEADS.size())
	for i in homestead_owner.size():
		homestead_owner[i] = String(owners[i]) if i < owners.size() else ""

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


# =============================================================
#  MULTIPLAYER — the shared half of the world
# -------------------------------------------------------------
# Only four things are shared: the soil, the pickups, the
# buildings, and who owns which homestead. Everything else in this
# file -- coins, seeds, basket, pouch, hunger, quests -- is yours
# alone and never leaves your machine.
#
# Every function below is one of three kinds, and it is worth
# knowing which you are looking at:
#
#   request_*   runs on YOUR machine. Asks, or just does it if you
#               are the host.
#   _host_*     runs on the HOST only. Decides, changes the world,
#               tells everyone.
#   _set_* / _apply_*  runs on EVERYONE. Takes what the host said
#               and makes it so. Never decides anything.
#
# There is no anti-cheat here and there should not be. This is four
# siblings on one wifi network; the failure mode we are designing
# against is confusion, not fraud.
# =============================================================

# --- Who owns what -------------------------------------------

## Which homestead does this plot belong to? -1 for the shared farm.
func homestead_of_plot(index: int) -> int:
	var shared := PLOT_COLS * PLOT_ROWS
	if index < shared:
		return -1
	var per := HOMESTEAD_COLS * HOMESTEAD_ROWS
	return (index - shared) / per


func owner_of_plot(index: int) -> String:
	var h := homestead_of_plot(index)
	if h < 0 or h >= homestead_owner.size():
		return ""
	return String(homestead_owner[h])


## The shared farm is everyone's. An unclaimed homestead is
## everyone's. A claimed one belongs to the kid who claimed it.
func may_harvest(index: int, actor_id: int) -> bool:
	var owner := owner_of_plot(index)
	if owner == "":
		return true
	return owner == Net.name_of(actor_id)


func my_homestead() -> int:
	for i in homestead_owner.size():
		if String(homestead_owner[i]) == Net.player_name and Net.player_name != "":
			return i
	return -1


# --- Claiming a homestead ------------------------------------

func request_claim(homestead: int) -> void:
	if Net.has_authority():
		_apply_personal(_host_claim(homestead, Net.my_id()))
	else:
		_req_claim.rpc_id(1, homestead)


func _host_claim(homestead: int, actor_id: int) -> Dictionary:
	if homestead < 0 or homestead >= homestead_owner.size():
		return {}
	var who := Net.name_of(actor_id)
	if who == "":
		return {}
	var current := String(homestead_owner[homestead])
	if current == who:
		return {"note": "This is already yours.", "colour": Palette.MOSS}
	if current != "":
		return {"sfx": "deny", "colour": Palette.UI_WARN,
			"note": "%s got here first. There are other clearings." % current}
	# One clearing each. Claiming a second releases the first, which
	# is friendlier than refusing and leaving them stuck.
	for i in homestead_owner.size():
		if String(homestead_owner[i]) == who:
			homestead_owner[i] = ""
	homestead_owner[homestead] = who
	_broadcast_claims()
	SaveManager.mark_dirty()
	return {"sfx": "chime", "colour": Palette.WARM_YELLOW,
		"note": "%s is yours now." % String(Terrain.HOMESTEADS[homestead]["name"])}


func _broadcast_claims() -> void:
	if Net.is_host():
		_set_claims.rpc(homestead_owner)
	roster_or_claims_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _set_claims(owners: Array) -> void:
	homestead_owner = owners
	roster_or_claims_changed.emit()
	plots_rebuilt.emit()


@rpc("any_peer", "call_remote", "reliable")
func _req_claim(homestead: int) -> void:
	if not Net.is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	_personal_result.rpc_id(from, _host_claim(homestead, from))


# --- Soil ----------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _req_plot(index: int, ctx: Dictionary) -> void:
	if not Net.is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	_personal_result.rpc_id(from, _host_plot_action(index, from, ctx))


func _broadcast_plot(index: int) -> void:
	if Net.is_host():
		_set_plot.rpc(index, plots[index].duplicate())


@rpc("authority", "call_remote", "reliable")
func _set_plot(index: int, data: Dictionary) -> void:
	if index < 0 or index >= plots.size():
		return
	# x and z are layout, not state -- they come from the terrain and
	# must never be overwritten by the wire.
	for k in ["state", "crop", "watered_at", "speed"]:
		if data.has(k):
			plots[index][k] = data[k]
	plot_changed.emit(index)


# --- Pickups -------------------------------------------------

func request_gather(node_id: int, material: String) -> void:
	if Net.has_authority():
		_apply_personal(_host_gather(node_id, material))
	else:
		_req_gather.rpc_id(1, node_id, material)


func _host_gather(node_id: int, material: String) -> Dictionary:
	if is_gathered(node_id):
		# Two kids grabbing the same mushroom is a normal race, not an
		# error. Whoever's packet arrived first gets it.
		return {"sfx": "deny", "colour": Palette.UI_TEXT_SOFT,
			"note": "Someone got there first."}
	gathered[node_id] = Time.get_unix_time_from_system() + Defs.GATHER_RESPAWN_SECONDS
	_broadcast_gathered(node_id)
	gathered_changed.emit(node_id)
	SaveManager.mark_dirty()
	return {"sfx": "pop", "gain_material": material, "colour": Palette.MOSS,
		"note": "Picked up a %s" % String(Defs.MATERIALS[material]["name"]).to_lower()}


func _broadcast_gathered(node_id: int) -> void:
	if Net.is_host():
		_set_gathered.rpc(node_id, float(gathered[node_id]))


@rpc("authority", "call_remote", "reliable")
func _set_gathered(node_id: int, regrow_at: float) -> void:
	gathered[node_id] = regrow_at
	gathered_changed.emit(node_id)


@rpc("any_peer", "call_remote", "reliable")
func _req_gather(node_id: int, material: String) -> void:
	if not Net.is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	_personal_result.rpc_id(from, _host_gather(node_id, material))


## Host only: hand back everything whose timer has run out, and tell
## the clients. Clients never expire pickups on their own, or four
## machines would disagree about the exact second.
func _host_regrow() -> void:
	if not Net.has_authority():
		return
	var back := take_regrown()
	if back.is_empty():
		return
	if Net.is_host():
		_set_regrown.rpc(back)


@rpc("authority", "call_remote", "reliable")
func _set_regrown(ids: Array) -> void:
	for id in ids:
		gathered.erase(int(id))
		gathered_changed.emit(int(id))


# --- Buildings -----------------------------------------------

func request_place(recipe_id: String, x: float, z: float, yaw: float) -> void:
	if Net.has_authority():
		_apply_personal(_host_place(recipe_id, x, z, yaw, Net.my_id()))
	else:
		_req_place.rpc_id(1, recipe_id, x, z, yaw)


func _host_place(recipe_id: String, x: float, z: float, yaw: float,
		actor_id: int, player_pos: Vector3 = Vector3.INF) -> Dictionary:
	var problem := placement_problem(recipe_id, x, z, player_pos)
	if problem != "":
		return {"sfx": "deny", "colour": Palette.UI_WARN, "note": problem}
	var entry := {"id": recipe_id, "x": x, "z": z, "yaw": yaw,
		"by": Net.name_of(actor_id)}
	if recipe_id == "hive":
		entry["filled_at"] = Time.get_unix_time_from_system()
	placed.append(entry)
	_broadcast_placed()
	SaveManager.mark_dirty()
	var out := {"sfx": "chime", "spend_build": recipe_id, "colour": Palette.MOSS,
		"note": "Placed a %s" % String(Defs.RECIPES[recipe_id]["name"])}
	if recipe_id == "house":
		out["bump"] = "houses"
		out["note"] = "A new home in Tendril Hills!"
		out["colour"] = Palette.DEEP_RED
	elif recipe_id == "scarecrow":
		out["bump"] = "scarecrows"
	return out


func _broadcast_placed() -> void:
	if Net.is_host():
		_set_placed.rpc(placed.duplicate(true))
	placed_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _set_placed(list: Array) -> void:
	placed = list
	placed_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _req_place(recipe_id: String, x: float, z: float, yaw: float) -> void:
	if not Net.is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	_personal_result.rpc_id(from, _host_place(recipe_id, x, z, yaw, from))


# --- Hives ---------------------------------------------------

func request_hive(index: int) -> void:
	if Net.has_authority():
		_apply_personal(_host_hive(index))
	else:
		_req_hive.rpc_id(1, index)


func _host_hive(index: int) -> Dictionary:
	if index < 0 or index >= placed.size():
		return {}
	var h: Dictionary = placed[index]
	if String(h.get("id", "")) != "hive":
		return {}
	if hive_progress(index) < 1.0:
		var left := int(ceilf(Defs.HIVE_SECONDS * (1.0 - hive_progress(index))))
		return {"sfx": "deny", "colour": Palette.UI_TEXT_SOFT,
			"note": "The bees are still working — about %ds" % left}
	h["filled_at"] = Time.get_unix_time_from_system()
	_broadcast_placed()
	SaveManager.mark_dirty()
	return {"sfx": "coin", "gain_crop": "honey", "gain_n": 1,
		"bump": "honey_taken", "colour": Palette.WARM_YELLOW,
		"note": "Collected a jar of honey!"}


@rpc("any_peer", "call_remote", "reliable")
func _req_hive(index: int) -> void:
	if not Net.is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	_personal_result.rpc_id(from, _host_hive(index))


# --- What the host tells you to do with your own pockets ------

@rpc("authority", "call_remote", "reliable")
func _personal_result(r: Dictionary) -> void:
	_apply_personal(r)


## Runs on the actor's machine only. The host has already decided;
## this just carries it out. Nothing here touches shared state.
func _apply_personal(r: Dictionary) -> void:
	if r.is_empty():
		return
	if r.has("sfx"):
		Sfx.play(String(r["sfx"]))
	if r.has("spend_seed"):
		var sid := String(r["spend_seed"])
		seeds[sid] = maxi(0, seed_count(sid) - 1)
		inventory_changed.emit()
	if r.has("gain_crop"):
		var crop := String(r["gain_crop"])
		var n := int(r.get("gain_n", 1))
		larder[crop] = int(larder.get(crop, 0)) + n
		# Honey comes out of a hive, not out of the ground, so it must
		# not count toward the harvest quests.
		if crop != "honey":
			for _i in n:
				_bump("%s_harvested" % crop)
				_bump("harvests")
		inventory_changed.emit()
	if r.has("gain_material"):
		var m := String(r["gain_material"])
		materials[m] = material_count(m) + 1
		_bump("gathered")
		materials_changed.emit()
	if r.has("spend_build"):
		var b := String(r["spend_build"])
		build_bag[b] = maxi(0, bag_count(b) - 1)
		if int(build_bag[b]) <= 0:
			build_bag.erase(b)
			if selected_build == b:
				cycle_build()
		inventory_changed.emit()
	if r.has("bump"):
		_bump(String(r["bump"]))
	if r.has("step"):
		_advance_onboarding(String(r["step"]))
	if r.has("note"):
		_note(String(r["note"]), r.get("colour", Palette.UI_TEXT))
	SaveManager.mark_dirty()
	_check_quests()


# --- Handing the world to somebody who just arrived -----------

## Host only. Called by Net when a client finishes connecting.
func send_world_to(id: int) -> void:
	if not Net.is_host():
		return
	var plot_state: Array = []
	for p in plots:
		plot_state.append({"state": p["state"], "crop": p["crop"],
			"watered_at": p["watered_at"], "speed": p.get("speed", 1.0)})
	_set_world.rpc_id(id, {
		"plots": plot_state,
		"gathered": gathered,
		"placed": placed,
		"owners": homestead_owner,
	})


@rpc("authority", "call_remote", "reliable")
func _set_world(d: Dictionary) -> void:
	# Note what is NOT in here: coins, seeds, basket, pouch, hunger,
	# quests. Joining somebody's world does not touch your things.
	var incoming: Array = d.get("plots", [])
	for i in mini(incoming.size(), plots.size()):
		var src: Dictionary = incoming[i]
		plots[i]["state"] = int(src.get("state", Soil.UNTILLED))
		plots[i]["crop"] = String(src.get("crop", ""))
		plots[i]["watered_at"] = float(src.get("watered_at", 0.0))
		plots[i]["speed"] = float(src.get("speed", 1.0))
	gathered = d.get("gathered", {})
	placed = d.get("placed", [])
	homestead_owner = d.get("owners", [])
	if homestead_owner.size() != Terrain.HOMESTEADS.size():
		homestead_owner.resize(Terrain.HOMESTEADS.size())
	plots_rebuilt.emit()
	placed_changed.emit()
	roster_or_claims_changed.emit()
	for id in gathered:
		gathered_changed.emit(int(id))
