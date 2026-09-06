shader_type spatial;
render_mode cull_disabled;

// Gate banner: a flag hanging off the pole (UV.x = 0) that flutters at its free end.
// Displacement is along local Z, the gate's travel axis (Race.js FLAG_WAVE).
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform float roughness = 0.7;
uniform float wave = 2.5;

void vertex() {
	float free = UV.x;
	float t = TIME * 3.0;
	VERTEX.z += sin(t + UV.x * 6.0 + UV.y * 1.5) * 0.1 * free * wave;
	VERTEX.y += sin(t * 0.7 + UV.x * 4.0) * 0.06 * free;
	NORMAL = normalize(vec3(-cos(t + UV.x * 6.0 + UV.y * 1.5) * 0.6 * free, 0.0, 1.0));
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(tex, UV);
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	EMISSION = emission * emission_energy;
}
