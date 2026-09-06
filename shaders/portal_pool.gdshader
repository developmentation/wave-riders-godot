shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "portal_common.gdshaderinc"

// Glow pool: the ring's light spilling onto the water around it.
uniform float pool_radius = 8.1;

varying vec2 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX.xy;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_local / pool_radius;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float shimmer = vnoise2(v_local * 0.9 + vec2(TIME * 0.35, -TIME * 0.27) + phase) * 0.6 + 0.7;
	float fall = pow(1.0 - r, 2.2);
	vec3 col = mix(deep, tint, 0.5 + 0.5 * fall) * 6.0 * shimmer * brightness;
	ALBEDO = portal_haze(col, length(v_world - CAMERA_POSITION_WORLD));
	ALPHA = fall * 0.6;
}
