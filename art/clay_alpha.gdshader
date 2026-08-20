// =============================================================
// clay_alpha.gdshader — see-through clay.
// -------------------------------------------------------------
// Same look as clay.gdshader, but writes ALPHA. Used only where
// transparency is actually wanted: the build-mode ghost house,
// the portal veil, water on freshly watered soil.
//
// ClayKit picks this automatically when you pass alpha < 1.0.
// =============================================================
shader_type spatial;
render_mode cull_back, diffuse_burley, depth_prepass_alpha;

#include "res://art/clay_core.gdshaderinc"

void fragment() {
	clay_shade(NORMAL, VIEW, ALBEDO, ROUGHNESS, SPECULAR, METALLIC, EMISSION, COLOR);
	ALPHA = alpha;
}
