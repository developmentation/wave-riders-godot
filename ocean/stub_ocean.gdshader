shader_type spatial;
render_mode cull_disabled;

// Stand-in ocean: three Gerstner-style waves matching StubOcean.gd's CPU function.
uniform vec4 wave0 = vec4(0.4, 60.0, 0.35, 0.6);   // amplitude, wavelength, direction (rad), steepness
uniform vec4 wave1 = vec4(0.2, 27.0, 0.85, 0.7);
uniform vec4 wave2 = vec4(0.1, 11.0, -0.55, 0.8);
uniform float time = 0.0;
uniform vec3 water_color : source_color = vec3(0.02, 0.28, 0.42);
uniform float foam_amount = 0.4;

varying float v_height;
varying float v_crest;

float wave_h(vec4 w, vec2 p, float t, out vec2 grad) {
	float k = 6.2831853 / w.y;
	float c = sqrt(9.81 / k);
	vec2 d = vec2(cos(w.z), sin(w.z));
	float phase = k * dot(d, p) - c * k * t;
	float h = w.x * cos(phase);
	grad = -w.x * k * sin(phase) * d;
	return h;
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 g0, g1, g2;
	float h = wave_h(wave0, p, time, g0) + wave_h(wave1, p, time, g1) + wave_h(wave2, p, time, g2);
	vec2 g = g0 + g1 + g2;
	VERTEX.y += h;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	v_height = h;
	v_crest = clamp(length(g) * 2.5 - 0.6, 0.0, 1.0);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(water_color, water_color * 1.8 + vec3(0.05, 0.1, 0.12), clamp(v_height * 0.6 + 0.3, 0.0, 1.0));
	float foam = smoothstep(0.55, 0.95, v_crest) * foam_amount;
	ALBEDO = mix(col, vec3(0.95), foam);
	ROUGHNESS = mix(0.08, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5 + fres * 0.4;
}
