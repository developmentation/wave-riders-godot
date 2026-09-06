shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
#include "portal_common.gdshaderinc"

// Tapered light column: fades with height, thin at the silhouette, slow rising haze.
uniform float column_h = 26.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	float h = clamp(v_local.y / column_h + 0.5, 0.0, 1.0);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 N = normalize(v_normal);
	// a cylinder of glowing haze is thickest through its middle
	float thick = pow(abs(dot(N, V)), 1.4);
	float ang = atan(v_local.z, v_local.x);
	float haze = vnoise2(vec2(ang * 1.5 + phase, h * 9.0 - TIME * 0.55));
	haze = 0.55 + 0.9 * haze;
	float fade = pow(1.0 - h, 1.8) * smoothstep(0.0, 0.08, h);
	float pulse = 0.9 + 0.1 * sin(TIME * 2.0 + phase);
	vec3 col = mix(deep, tint, 0.6 + 0.4 * h) * 6.5 * haze * pulse * brightness;
	float alpha = fade * thick * 0.42 * haze;
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = portal_haze(col, length(v_world - CAMERA_POSITION_WORLD));
	ALPHA = alpha;
}
