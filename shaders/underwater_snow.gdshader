shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;

// Marine snow: GPUParticles3D quads drawn as fixed-pixel-size soft dots that fade out toward the
// fog and in over the first metres in front of the lens. COLOR.a (particle alpha) scales the dot.
uniform vec3 tint : source_color = vec3(0.3, 0.8, 0.9);
uniform float size_px = 4.0;
uniform float fade_near = 18.0;
uniform float fade_far = 27.0;
uniform float bubble_fraction = 0.3;

varying float v_fade;
varying float v_bubble;

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	float dist = length(vp.xyz);
	// per-particle size jitter and bubble flag from the particle's random seed (COLOR.r/g)
	v_bubble = step(1.0 - bubble_fraction, COLOR.g);
	float px = size_px * mix(0.7, 1.4, COLOR.r) * mix(1.0, 1.35, v_bubble);
	float world_size = px * dist * 2.0 / (VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1]);
	vp.xy += VERTEX.xy * world_size;
	POSITION = PROJECTION_MATRIX * vp;
	v_fade = (1.0 - smoothstep(fade_near, fade_far, dist)) * smoothstep(1.0, 4.0, dist) * COLOR.a;
}

void fragment() {
	float r = length(UV - 0.5);
	float a = smoothstep(0.5, 0.12, r) * v_fade * 0.6;
	ALBEDO = tint * mix(1.0, 1.5, v_bubble);
	ALPHA = a;
}
