// Shared bits of the portal glow shaders (port of GLOW_COMMON in src/game/Portals.js).
uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.3);
uniform vec3 deep : source_color = vec3(1.0, 0.54, 0.1);
uniform float phase = 0.0;
uniform float fog_density = 0.0;          // storm haze; the sky module may drive this
uniform vec3 haze_color : source_color = vec3(0.55, 0.62, 0.72);
uniform float brightness = 0.32;          // web HDR values scaled for Godot's tonemapper + glow

float p_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = p_hash21(i);
	float b = p_hash21(i + vec2(1.0, 0.0));
	float c = p_hash21(i + vec2(0.0, 1.0));
	float d = p_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 portal_haze(vec3 color, float dist) {
	float fog = 1.0 - exp(-dist * fog_density * 0.0025);
	return mix(color, haze_color * 2.2, fog * 0.8);
}
