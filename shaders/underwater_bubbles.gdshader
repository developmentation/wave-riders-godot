shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;

// Submarine bubble trail (GPUParticles3D). Each bubble is a billboard quad with a thin bright rim,
// a faint fill and a highlight; it grows with age, wobbles, and is clamped just below the sea
// surface (`surface_y`, set per frame) where it fades out. INSTANCE_CUSTOM.y is the lifetime
// phase (0..1); COLOR.rg carries the particle's random seed.
uniform vec3 tint : source_color = vec3(0.75, 0.92, 1.0);
uniform float surface_y = 0.0;
uniform float life = 3.2;
uniform float min_px = 1.5;
uniform float max_px = 14.0;

varying float v_fade;
varying float v_seed;

void vertex() {
	float t = INSTANCE_CUSTOM.y;
	float age = t * life;
	float seed = COLOR.g;
	vec3 wp = MODEL_MATRIX[3].xyz;
	float spread = 0.5 + COLOR.r;
	wp.x += sin(age * 2.6 + seed * 21.0) * 0.12 * age * spread;
	wp.z += cos(age * 2.1 + seed * 13.0) * 0.12 * age * spread;
	float to_surf = surface_y - 0.15 - wp.y;
	wp.y = min(wp.y, surface_y - 0.15);
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	float dist = max(length(vp.xyz), 0.05);
	// scale comes from the instance transform (particle scale): the bubble's diameter in metres
	float diam = length(MODEL_MATRIX[0].xyz) * (1.0 + age * 0.35);
	float px_per_m = VIEWPORT_SIZE.y * PROJECTION_MATRIX[1][1] * 0.5 / dist;
	float px = clamp(diam * px_per_m, min_px, max_px);
	float world_size = px / px_per_m;
	vp.xy += VERTEX.xy * world_size;
	POSITION = PROJECTION_MATRIX * vp;
	v_fade = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.75, 1.0, t)) * smoothstep(-0.2, 0.6, to_surf);
	v_seed = seed;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float rim = smoothstep(0.55, 0.85, d) * (1.0 - smoothstep(0.88, 1.0, d));
	float fill = (1.0 - d) * 0.18;
	float hi = pow(max(0.0, 1.0 - length(q - vec2(-0.35, 0.35)) * 2.4), 2.0);
	float a = (rim * 0.55 + fill * 0.6 + hi * 0.8) * v_fade;
	if (d > 1.0) {
		a = 0.0;
	}
	ALBEDO = tint * (1.0 + hi * 1.5);
	ALPHA = clamp(a, 0.0, 1.0);
}
