#[compute]
#version 450
/**
 * Unpacks the IFFT output into the displacement map (dx, dy, dz, J-1) and the normal map
 * (dh/dx, dh/dz, foam, bubbles). Foam grows where the Jacobian folds (J < whitecap) and decays
 * over seconds; bubbles are the long-lived raft left behind (tens of seconds).
 */
#define TILE_SIZE   (16U)
#define NUM_SPECTRA (4U)
layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict writeonly uniform image2DArray displacement_map;
layout(rgba16f, set = 0, binding = 1) restrict uniform image2DArray normal_map;
layout(std430, set = 0, binding = 2) restrict readonly buffer FFTBuffer {
	vec2 data[];
};

layout(std140, set = 0, binding = 3) uniform CascadeParams {
	vec4 tile_depth_time[3];   // tile_x, tile_y, depth, time
	vec4 foam_a[3];            // whitecap, foam_grow, foam_decay, bubble_grow
	vec4 foam_b[3];            // bubble_decay, dt, displacement_scale, 0
};

#define FFT_DATA(id, layer) (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + NUM_SPECTRA * map_size * map_size + (layer) * map_size * map_size + (id).y * map_size + (id).x])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const uint cascade_index = gl_WorkGroupID.z;
	if (foam_b[cascade_index].w > 0.5) return;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	const float whitecap = foam_a[cascade_index].x;
	const float foam_grow = foam_a[cascade_index].y;
	const float foam_decay = foam_a[cascade_index].z;
	const float bubble_grow = foam_a[cascade_index].w;
	const float bubble_decay = foam_b[cascade_index].x;
	const float dt = foam_b[cascade_index].y;
	const float displacement_scale = foam_b[cascade_index].z;
	const float sign_shift = -2.0 * float((id.x & 1) ^ (id.y & 1)) + 1.0;

	vec2 d0 = FFT_DATA(id, 0) * sign_shift;
	vec2 d1 = FFT_DATA(id, 1) * sign_shift;
	vec2 d2 = FFT_DATA(id, 2) * sign_shift;
	vec2 d3 = FFT_DATA(id, 3) * sign_shift;

	float hx = d0.x, hy = d0.y, hz = d1.x;
	float dhy_dx = d1.y, dhy_dz = d2.x, dhx_dx = d2.y, dhz_dz = d3.x, dhz_dx = d3.y;

	float s = displacement_scale;
	float jacobian = (1.0 + s * dhx_dx) * (1.0 + s * dhz_dz) - s * s * dhz_dx * dhz_dx;
	float fold = clamp((whitecap - jacobian) * 3.0, 0.0, 1.0);

	vec4 prev = imageLoad(normal_map, id);
	float foam = prev.z * exp(-foam_decay * dt) + fold * foam_grow * dt;
	float bubbles = prev.w * exp(-bubble_decay * dt) + fold * bubble_grow * dt;

	vec2 gradient = vec2(dhy_dx, dhy_dz) / (1.0 + abs(vec2(dhx_dx, dhz_dz)) * s);
	imageStore(displacement_map, id, vec4(hx, hy, hz, jacobian - 1.0));
	imageStore(normal_map, id, vec4(gradient, clamp(foam, 0.0, 1.0), clamp(bubbles, 0.0, 1.0)));
}
