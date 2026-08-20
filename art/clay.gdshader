// =============================================================
// clay.gdshader — the look of the whole game (opaque version).
// -------------------------------------------------------------
// Art Bible §1: "sculpted from clay by loving hands. Soft edges,
// visible texture, warm imperfection. Nothing perfectly smooth."
//
// Three tricks do all the work:
//   1. WOBBLE  — pushes each vertex slightly along its normal
//                using 3D noise, so no surface is ever machine-flat.
//   2. GRAIN   — tints the surface with the same noise so you can
//                read the thumbprints in the clay.
//   3. WRAP    — a custom light() that wraps light around the
//                terminator, the way soft matte clay actually
//                behaves. This is what kills the "3D primitive" look.
//
// Specular is off everywhere except mushroom caps (Art Bible §4.1:
// "slight gloss on mushroom caps only") — pass gloss > 0 for those.
//
// The transparent twin lives in clay_alpha.gdshader. Keeping them
// apart matters: a shader that writes ALPHA is treated as
// transparent by Godot for ALL of its geometry, which would cost
// the whole world its depth prepass and its correct sorting.
// =============================================================
shader_type spatial;
render_mode cull_back, diffuse_burley;

#include "res://art/clay_core.gdshaderinc"

void fragment() {
	clay_shade(NORMAL, VIEW, ALBEDO, ROUGHNESS, SPECULAR, METALLIC, EMISSION, COLOR);
}
