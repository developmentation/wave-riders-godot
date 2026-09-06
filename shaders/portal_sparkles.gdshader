shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
#include "portal_common.gdshaderinc"

// Sparkles rising through the ring: camera-facing quads placed entirely in the vertex shader from
// a per-quad seed (CUSTOM0.xyz); UV is the corner offset in [-1, 1].
uniform float ring_radius = 6.0;
uniform float ring_y = 4.6;

varying float v_fade;
varying float v_twinkle;
varying vec2 v_q;

void vertex() {
	vec3 seed = CUSTOM0.xyz;
	float speed = mix(0.9, 1.9, seed.z);
	float life = fract(TIME * speed * 0.14 + seed.x * 7.0 + phase);
	float rad = ring_radius * 0.92 * sqrt(seed.x);
	float ang = seed.y * 6.2831853 + life * 2.2 + TIME * 0.15;
	vec3 local = vec3(cos(ang) * rad, mix(-1.5, ring_radius * 2.0 + 3.0, life), (seed.z - 0.5) * 2.4);
	// pull them toward the ring's centre as they climb so the cloud reads as a fountain
	local.xz *= mix(1.0, 0.35, life * life);
	local.y += ring_y - ring_radius;
	vec3 wp = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	float dist = length(CAMERA_POSITION_WORLD - wp);
	// a few pixels at any distance: world half-size grows with distance
	float half_size = mix(0.16, 0.30, seed.y) + dist * 0.0028;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	VERTEX = wp + (right * UV.x + up * UV.y) * half_size;
	v_q = UV;
	v_fade = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.7, 1.0, life));
	v_twinkle = 0.55 + 0.45 * sin(TIME * mix(5.0, 11.0, seed.y) + seed.x * 40.0);
}

void fragment() {
	vec2 q = v_q;
	float d = length(q);
	if (d > 1.0) {
		discard;
	}
	// soft core plus a four-point star
	float core = pow(1.0 - d, 2.2);
	float ax = pow(max(1.0 - abs(q.y), 0.0), 10.0) * pow(max(1.0 - abs(q.x), 0.0), 1.5);
	float ay = pow(max(1.0 - abs(q.x), 0.0), 10.0) * pow(max(1.0 - abs(q.y), 0.0), 1.5);
	float a = (core + max(ax, ay) * 0.6) * v_fade * v_twinkle;
	if (a < 0.01) {
		discard;
	}
	ALBEDO = mix(tint, vec3(1.0), core * 0.7) * 16.0 * brightness;
	ALPHA = clamp(a, 0.0, 1.0);
}
