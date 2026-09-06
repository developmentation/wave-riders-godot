shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// Flat-colour toy material for the submarine's opaque parts: like StandardMaterial3D's albedo,
// roughness, metallic and emission, plus the water column's absorption with depth below
// `sea_level` so a sub at 40 m looks dim and blue like the seabed around it.
uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.5;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float sea_level = 0.0;
uniform vec3 absorb = vec3(0.045, 0.015, 0.006);

varying float v_depth;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = max(sea_level - wp.y, 0.0);
}

void fragment() {
	vec3 att = exp(-absorb * v_depth);
	ALBEDO = albedo * att;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	EMISSION = emission * emission_energy;
}
