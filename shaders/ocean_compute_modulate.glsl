#[compute]
#version 450
/** Time-evolves the spectrum and packs h, the horizontal displacements and the gradients as pairs of real signals. */
#define PI          (3.141592653589793)
#define G           (9.81)
#define NUM_SPECTRA (4U)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;
layout(std430, set = 0, binding = 1) restrict writeonly buffer FFTBuffer {
	vec2 data[];
};

layout(std140, set = 0, binding = 2) uniform CascadeParams {
	vec4 tile_depth_time[3];   // tile_x, tile_y, depth, time
	vec4 foam_a[3];            // whitecap, foam_grow, foam_decay, bubble_grow
	vec4 foam_b[3];            // bubble_decay, dt, displacement_scale, 0
};

vec2 exp_complex(in float x) { return vec2(cos(x), sin(x)); }
vec2 mul_complex(in vec2 a, in vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 conj_complex(in vec2 x) { return vec2(x.x, -x.y); }
float dispersion_relation(in float k, in float depth) { return sqrt(G * k * tanh(k * depth)); }

#define FFT_DATA(id, layer) (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + (layer) * map_size * map_size + (id.y) * map_size + (id.x)])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const ivec2 dims = imageSize(spectrum).xy;
	const uint cascade_index = gl_WorkGroupID.z;
	if (foam_b[cascade_index].w > 0.5) return;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	const vec2 tile_length = tile_depth_time[cascade_index].xy;
	const float depth = tile_depth_time[cascade_index].z;
	const float time = tile_depth_time[cascade_index].w;

	vec2 k_vec = vec2(id.xy - dims / 2) * 2.0 * PI / tile_length;
	float k = length(k_vec) + 1e-6;
	vec2 k_unit = k_vec / k;

	vec4 h0 = imageLoad(spectrum, id);
	vec2 modulation = exp_complex(dispersion_relation(k, depth) * time);
	vec2 h = mul_complex(h0.xy, modulation) + mul_complex(h0.zw, conj_complex(modulation));
	vec2 h_inv = vec2(-h.y, h.x);

	vec2 hx = h_inv * k_unit.y;
	vec2 hy = h;
	vec2 hz = h_inv * k_unit.x;
	vec2 dhy_dx = h_inv * k_vec.y;
	vec2 dhy_dz = h_inv * k_vec.x;
	vec2 dhx_dx = -h * k_vec.y * k_unit.y;
	vec2 dhz_dz = -h * k_vec.x * k_unit.x;
	vec2 dhz_dx = -h * k_vec.y * k_unit.x;

	FFT_DATA(id, 0) = vec2(hx.x - hy.y, hx.y + hy.x);
	FFT_DATA(id, 1) = vec2(hz.x - dhy_dx.y, hz.y + dhy_dx.x);
	FFT_DATA(id, 2) = vec2(dhy_dz.x - dhx_dx.y, dhy_dz.y + dhx_dx.x);
	FFT_DATA(id, 3) = vec2(dhz_dz.x - dhz_dx.y, dhz_dz.y + dhz_dx.x);
}
