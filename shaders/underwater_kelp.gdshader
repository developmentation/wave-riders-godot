shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert, specular_schlick_ggx;

// Kelp ribbons (MultiMesh). The ribbon mesh is 1 m tall (UV.y = height fraction, 0 root .. 1 tip)
// and the instance transform scales it to the strand's width/height. INSTANCE_CUSTOM.x is a
// per-strand phase, .y the lean (metres at the tip). Slow sway with two lobes so the fronds do
// not all nod together; the tip travels `wave` metres — PropMaterial's KELP_WAVE.
uniform float wave = 0.9;
uniform float sea_level = 0.0;
uniform vec3 absorb = vec3(0.045, 0.015, 0.006);

varying float v_depth;

void vertex() {
	float hf = UV.y;
	float sway = hf * hf * wave;
	float ph = TIME * 0.9 + INSTANCE_CUSTOM.x * 6.2831853;
	VERTEX.x += (sin(ph) + 0.35 * sin(ph * 2.3 + VERTEX.z * 0.7)) * sway + INSTANCE_CUSTOM.y * hf * hf;
	VERTEX.z += cos(ph * 0.8 + 1.7) * sway * 0.6;
	v_depth = max(sea_level - VERTEX.y, 0.0);
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = n;
	ALBEDO = COLOR.rgb * exp(-absorb * v_depth);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
