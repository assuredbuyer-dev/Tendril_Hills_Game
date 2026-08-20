# =============================================================
# palette.gd — the Art Bible, in code.
# -------------------------------------------------------------
# Every colour in Tendril Hills comes from here. Nothing in the
# project is allowed to hardcode a hex value. Change a colour
# here and the whole world reskins.
#
# Source: 0. Tendril Hills Master Plan/04_Tendril_Hills_Art_Bible.md §3
# =============================================================
class_name Palette
extends RefCounted

# --- 3.1 World palette ---------------------------------------
const CREAM        := Color("F5EFE0")  # mushroom stems, sprite skin base
const EARTH        := Color("8B6048")  # fence, doors, roots, soil
const MOSS         := Color("7B9E5A")  # grass, leaves
const DEEP_RED     := Color("B83232")  # mushroom caps, radish
const CARROT       := Color("E87A30")  # carrots, autumn accents
const WARM_YELLOW  := Color("F2C94C")  # flowers, sunlight accents
const SKY_BLUE     := Color("A8D4E6")  # water, sky
const SOFT_PURPLE  := Color("9B7EC8")  # turnip, rare accents
const CLAY_TAN     := Color("C4956A")  # skin tones, soil base
const STONE        := Color("9E9E8E")  # paths, stone

# Derived shades — kept here so tints stay consistent
const MOSS_DARK    := Color("5F7C43")
const MOSS_LIGHT   := Color("94B36C")
const EARTH_DARK   := Color("6B4835")
const SOIL_DRY     := Color("7C5A3E")
const SOIL_WET     := Color("5C3F2C")
const LEAF         := Color("6E9450")
const ROSY         := Color("E39A8C")
const EYE_DARK     := Color("3D2B1F")

# --- 3.2 Rarity lane -----------------------------------------
const RARITY := {
	"common":    Color("F5EFE0"),
	"uncommon":  Color("7FCE7F"),
	"rare":      Color("5AADDA"),
	"epic":      Color("B57FE8"),
	"legendary": Color("FFD166"),
}

# --- 3.3 UI palette ------------------------------------------
const UI_PANEL     := Color("FAF3E0")
const UI_PANEL_DIM := Color("EFE3C8")
const UI_BUTTON    := Color("8B6048")
const UI_HOVER     := Color("B83232")
const UI_TEXT      := Color("3D2B1F")
const UI_TEXT_SOFT := Color("7A5C44")
const UI_ACCENT    := Color("7B9E5A")
const UI_WARN      := Color("E87A30")
const UI_SHADOW    := Color(0.24, 0.17, 0.12, 0.25)

# --- Lighting mood (Art Bible §7: late afternoon golden) -----
const SUN_COLOR    := Color("FFE7BF")
const AMBIENT_SKY  := Color("BFD9E8")
const AMBIENT_GRND := Color("C9B08A")
const FOG_COLOR    := Color("E8DCC2")
