// clay_core.gdshaderinc — shared guts of the clay look.
// Included by clay.gdshader (opaque) and clay_alpha.gdshader.
// See clay.gdshader for the design notes.

uniform vec3  clay_color : source_color = vec3(0.77, 0.58, 0.42);
uniform vec3  rim_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float wobble : hint_range(0.0, 0.2) = 0.018;
uniform float grain : hint_range(0.0, 0.5) = 0.10;
uniform float noise_scale : hint_range(0.5, 40.0) = 7.0;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;
uniform vec3  emission_color : source_color = vec3(0.0);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;
uniform float wrap_amount : hint_range(0.0, 1.0) = 0.38;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Terrain paints patchy grass/dirt into vertex colours; props leave this at 0.
uniform float vertex_color_amount : hint_range(0.0, 1.0) = 0.0;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	float n = vnoise(VERTEX * noise_scale) - 0.5;
	VERTEX += NORMAL * n * wobble;
}

// Shared fragment body. Both shader variants call this; only the
// alpha variant writes ALPHA, so opaque geometry keeps its depth
// prepass and correct sorting.
void clay_shade(vec3 normal, vec3 view, inout vec3 albedo, inout float roughness,
		inout float specular, inout float metallic, inout vec3 emission, vec4 vcol) {
	// Fine surface grain — the thumbprints.
	float g = vnoise(v_local * noise_scale * 2.3);
	vec3 tint = mix(vec3(1.0), vcol.rgb, vertex_color_amount);
	vec3 base = clay_color * tint * (1.0 - grain * 0.5 + grain * g);

	// Warm fresnel rim: light bleeding through the edge of a thick
	// matte material. Cheap subsurface, essentially.
	float f = pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), 3.0);

	albedo = base + rim_color * f * rim_strength;
	roughness = mix(1.0, 0.35, gloss);
	specular = gloss * 0.5;
	metallic = 0.0;
	emission = emission_color * emission_strength;
}


void light() {
	// Wrapped diffuse. Instead of light cutting off hard at the
	// terminator (dot == 0), it wraps around to the shadow side,
	// which is exactly how soft matte clay reads to the eye.
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float wrapped = clamp((ndl + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * wrapped * ALBEDO * (1.0 / PI);

	if (gloss > 0.001) {
		vec3 h = normalize(normalize(LIGHT) + normalize(VIEW));
		float spec = pow(max(dot(normalize(NORMAL), h), 0.0), 24.0);
		SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * spec * gloss * 0.35;
	}
}
