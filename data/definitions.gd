# =============================================================
# definitions.gd — All game data in one place (Tendrel Studios)
# -------------------------------------------------------------
# WHY THIS FILE EXISTS:
# Every crop, building, quest and price lives here so the whole
# economy can be rebalanced without touching a line of game logic.
# Add a crop to CROPS and it appears in the shop, the seed pouch,
# the planting code and the save file for free.
#
# Carried forward from the 2D scaffold so the tuning work already
# done is not lost.
# =============================================================
class_name Defs
extends RefCounted

# Grow times in SECONDS. The GDD ships 300 (carrot) / 180 (radish);
# these are the shortened playtest values. See ROADMAP M1.
const CROPS := {
	"carrot": {
		"name": "Carrot", "grow": 45.0, "hunger": 20,
		"coins": 3, "seed_cost": 5, "rarity": "common",
		"color": Color("E87A30"), "leaf": Color("6E9450"),
	},
	"radish": {
		"name": "Radish", "grow": 25.0, "hunger": 10,
		"coins": 2, "seed_cost": 4, "rarity": "common",
		"color": Color("B83232"), "leaf": Color("7B9E5A"),
	},
	"turnip": {
		"name": "Turnip", "grow": 70.0, "hunger": 30,
		"coins": 6, "seed_cost": 9, "rarity": "uncommon",
		"color": Color("9B7EC8"), "leaf": Color("6E9450"),
	},
	# Honey comes out of a hive, never out of the ground. `plantable`
	# false keeps it out of the seed pouch, the shop and the planting
	# code while still letting you eat it and sell it.
	"honey": {
		"name": "Honey", "grow": 0.0, "hunger": 45,
		"coins": 12, "seed_cost": 0, "rarity": "rare", "plantable": false,
		"color": Color("F2C94C"), "leaf": Color("E8A33D"),
	},
}

## Crops you can actually put in the soil.
static func plantable_crops() -> Array:
	var out: Array = []
	for id in CROPS:
		if bool(CROPS[id].get("plantable", true)):
			out.append(id)
	return out

# Superseded by RECIPES below — buildings are crafted from gathered
# materials now, not bought with coins. Kept only so older save files
# and the quest table still resolve their names.
const BUILDS := {
	"plot":  {"name": "Farm Plot",      "desc": "A patch of tillable soil"},
	"house": {"name": "Mushroom House", "desc": "A cozy clay home"},
	"fence": {"name": "Fence Post",     "desc": "Clay fence, snaps to your farm"},
}

const QUESTS := [
	{"id": "q1", "text": "Harvest 3 carrots",      "key": "carrot_harvested", "target": 3, "reward": 40},
	{"id": "q2", "text": "Water your crops 5 times", "key": "waters",         "target": 5, "reward": 25},
	{"id": "q3", "text": "Eat something you grew",  "key": "meals",           "target": 1, "reward": 20},
	{"id": "q4", "text": "Place a mushroom house",  "key": "houses",          "target": 1, "reward": 80},
	{"id": "q5", "text": "Harvest 5 radishes",      "key": "radish_harvested","target": 5, "reward": 45},
	{"id": "q6", "text": "Grow a turnip",           "key": "turnip_harvested","target": 1, "reward": 90},
	{"id": "q7", "text": "Gather 10 things from the meadow", "key": "gathered", "target": 10, "reward": 35},
	{"id": "q8", "text": "Craft something at the workbench",  "key": "crafted",  "target": 1,  "reward": 50},
	{"id": "q9", "text": "Put up a scarecrow",                "key": "scarecrows","target": 1, "reward": 60},
	{"id": "q10","text": "Collect honey from a hive",         "key": "honey_taken","target": 1,"reward": 70},
]

# Old Sprout's onboarding lines — World Design §3.
const ONBOARDING := [
	{"id": "welcome",  "who": "Old Sprout", "text": "Welcome, little sprite! Tendril Hills has been waiting for someone to tend it."},
	{"id": "gift",     "who": "Old Sprout", "text": "Here — three carrot seeds and my old watering can. Go find the soil east of here."},
	{"id": "till",     "who": "",           "text": "Walk to a patch of soil and press E to turn it over."},
	{"id": "plant",    "who": "",           "text": "Press E again on the tilled soil to tuck a seed in."},
	{"id": "water",    "who": "",           "text": "Now press E once more to water it. Clay soil drinks deep."},
	{"id": "wait",     "who": "Old Sprout", "text": "Now we wait. Roots keep growing even when you close the game, you know."},
	{"id": "harvest",  "who": "",           "text": "It's ready! Press E to pull it up."},
	{"id": "eat",      "who": "",           "text": "Press 1 to eat it. A sprite has to keep their belly full."},
	{"id": "free",     "who": "Old Sprout", "text": "Tendril Hills is yours to tend. Sell at the stall, and mind that old root archway to the west..."},
]

const PORTAL_QUESTS_REQUIRED := 5   # GDD says 10; slice teases at 5.
const STARTING_COINS := 20

# --- Hunger -------------------------------------------------------
# WHY 22 AND NOT 6: at 1 point per 6s, a full belly empties in 10
# minutes. A carrot is worth 20 points = 200 seconds of belly, but at
# the GDD's shipping grow time it takes 300 seconds to produce. The
# loop went negative the moment the playtest timers were restored --
# you could farm perfectly and still starve. At 22s a carrot buys 440
# seconds for 300 seconds of growing, so one plot keeps you alive and
# every plot after that is surplus to sell. Radish is the tightest
# crop at 220s bought for 180s grown, which is the intent: the cheap
# seed is a stopgap, not a living.
const HUNGER_DRAIN_SECONDS := 22.0  # 1 hunger point every N seconds

# Hunger is a carrot, not a stick. Nothing bad happens at zero -- this
# is a cozy game and a seven-year-old should never be punished for
# wandering off. Instead a full belly is worth chasing.
const HUNGER_WELL_FED := 70.0       # at or above: bouncy, lucky
const HUNGER_PECKISH := 20.0        # at or below: slow, a gentle nudge
const SPEED_WELL_FED := 1.12
const SPEED_PECKISH := 0.86
const WELL_FED_BONUS_CHANCE := 0.25 # chance of a second crop on harvest
const START_SEEDS := {"carrot": 3, "radish": 2}

# --- Gathering ----------------------------------------------------
# Things lying around the world that you pick up by walking over and
# pressing E. They regrow, always — a cozy world that can be stripped
# bare and never recovers is a world you stop wanting to walk around
# in. The respawn is a timestamp, same trick as crops, so the meadow
# refills while the game is closed.
const MATERIALS := {
	"toadstool": {"name": "Toadstool", "colour": Color("B83232")},
	"stone":     {"name": "Stone",     "colour": Color("9E9E8E")},
	"branch":    {"name": "Branch",    "colour": Color("6B4835")},
}

const GATHER_RESPAWN_SECONDS := 150.0

# --- Recipes ------------------------------------------------------
# WHY BUILDING COSTS MATERIALS AND NOT COINS:
# Two currencies, two jobs. Coins come from farming and buy seeds.
# Materials come from walking around and build things. Before this,
# building was "sell crops, press 3" — the world outside the farm was
# scenery. Now the meadow is a reason to leave the fence.
#
# To put the old coin cost back, give a recipe a "coins" key and drop
# its "cost" entries. Nothing else needs to change.
# ONE ENTRY PER CRAFTABLE — this table is the whole registry.
#
#   name   what the workbench calls it
#   cost   materials it eats
#   build  the function in art/props.gd that sculpts it. The world and
#          the build-mode ghost both call Props by this name, so you
#          never have to edit them.
#   solid  [radius, height] the Sprite bumps into. Omit for things you
#          walk over, like a path stone.
#   block  [radius, height] the CAMERA bumps into (layer 3). Only worth
#          it for something tall enough to bury the lens.
#   space  how much clear ground it needs, and how far from the Sprite
#   act    an interaction kind, if walking up to it should do something
#
# ADDING YOUR OWN: write a function in props.gd, add a row here. That
# is the entire job — see docs/MAKE_A_THING.md.
const RECIPES := {
	"fence": {
		"name": "Fence Post", "cost": {"branch": 2}, "build": "fence_post",
		"solid": [0.24, 1.0], "space": 0.7,
		"desc": "A clay post. Line them up.",
	},
	"path": {
		"name": "Path Stone", "cost": {"stone": 2}, "build": "path_stone",
		"space": 0.6,
		"desc": "A worn stepping stone. Walk right over it.",
	},
	"planter": {
		"name": "Flower Planter", "cost": {"stone": 2, "toadstool": 1},
		"build": "planter", "solid": [0.42, 0.7], "space": 1.0,
		"desc": "A pot of clay blooms.",
	},
	"sign": {
		"name": "Signpost", "cost": {"branch": 3}, "build": "player_sign",
		"solid": [0.2, 1.3], "space": 0.9,
		"desc": "Point the way. Or don't.",
	},
	"lantern": {
		"name": "Clay Lantern", "cost": {"stone": 3, "branch": 2, "toadstool": 1},
		"build": "lantern", "solid": [0.3, 1.8], "space": 1.0,
		"desc": "Pools warm light on the ground.",
	},
	"scarecrow": {
		"name": "Scarecrow", "cost": {"branch": 6, "toadstool": 3, "stone": 1},
		"build": "scarecrow", "solid": [0.4, 2.0], "block": [1.0, 2.6], "space": 1.8,
		"desc": "Crops nearby grow half again as fast.",
	},
	"hive": {
		"name": "Bee Hive", "cost": {"branch": 5, "toadstool": 4},
		"build": "hive", "solid": [0.55, 1.2], "space": 1.6, "act": "hive",
		"desc": "Fills with honey. Come back for it.",
	},
	"house": {
		"name": "Mushroom House", "cost": {"toadstool": 10, "branch": 8, "stone": 6},
		"build": "mushroom_house", "solid": [1.35, 2.2], "block": [2.0, 3.4],
		"space": 3.2,
		"desc": "A cozy clay home.",
	},
}

# --- What the placeables DO --------------------------------------
# A decoration you place once and never think about again is a weak
# reward. These two pay you back for building them.
const SCARECROW_RADIUS := 7.0      # how far its help reaches
const SCARECROW_BONUS := 0.5       # +50% growth speed, capped below
const SCARECROW_MAX_BONUS := 1.0   # two scarecrows help; ten do not
const HIVE_SECONDS := 240.0        # how long a hive takes to fill

## Clear ground a placeable needs — read off its recipe row.
static func clearance(recipe_id: String) -> float:
	if RECIPES.has(recipe_id):
		return float(RECIPES[recipe_id].get("space", 1.0))
	return 1.0

