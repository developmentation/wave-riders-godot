shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// Flat-shaded, face-coloured seabed (The Deep Run). Vertex colours are linear. Daylight is
// attenuated with depth below `sea_level` (red first) so the sand reads turquoise near the
// surface and deep blue at the canyon floor — the web PropMaterial's uSubAbsorb.
uniform float sea_level = 0.0;
uniform vec3 absorb = vec3(0.045, 0.015, 0.006);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.92;

varying float v_depth;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = max(sea_level - wp.y, 0.0);
}

void fragment() {
	ALBEDO = COLOR.rgb * exp(-absorb * v_depth);
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
