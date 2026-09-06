shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "portal_common.gdshaderinc"

// Liquid light: a translucent window whose swirling filaments brighten toward a soft rim.
uniform float ring_radius = 6.0;

varying vec2 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX.xy;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_local / ring_radius;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float t = TIME * 0.8 + phase;
	float ang = atan(p.y, p.x);
	// domain-warped swirl: the angle advances with radius so the field twists
	float swirl = ang + r * 2.6 - t * 0.3;
	vec2 q = vec2(cos(swirl), sin(swirl)) * (0.6 + r * 2.2);
	float n1 = vnoise2(q * 1.7 + vec2(t * 0.25, -t * 0.2));
	float n2 = 0.5 + 0.5 * sin(swirl * 5.0 + r * 9.0 - t * 1.2 + n1 * 3.5);
	float fil = smoothstep(0.42, 0.62, n1 * 0.55 + n2 * 0.45);            // bright liquid filaments
	float rip = pow(sin(r * 14.0 - t * 2.4 + n1 * 3.0) * 0.5 + 0.5, 4.0);  // a few soft ripples
	float rim = smoothstep(0.60, 0.97, r);
	float rim_core = smoothstep(0.90, 0.99, r);
	vec3 col = mix(deep, tint, clamp(r * 0.45 + fil * 0.7 - 0.1, 0.0, 1.0)) * (2.2 + fil * 6.5 + rip * 3.0);
	col += tint * rim * 6.0 + vec3(1.0) * rim_core * 4.0;
	col *= brightness;
	// see-through in the middle so the world behind shimmers through the light
	float alpha = 0.10 + fil * 0.40 + rip * 0.15 + rim * 0.45;
	alpha = clamp(alpha, 0.0, 0.8) * (1.0 - smoothstep(0.985, 1.0, r));
	ALBEDO = portal_haze(col, length(v_world - CAMERA_POSITION_WORLD));
	ALPHA = alpha;
}
