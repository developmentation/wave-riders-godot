#[compute]
#version 450
/** Coalesced decimation-in-time Stockham FFT over rows. MAP_SIZE is injected at compile time. */
#ifndef MAP_SIZE
#define MAP_SIZE 256
#endif
#define NUM_SPECTRA (4U)

layout(local_size_x = MAP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer ButterflyBuffer {
	vec4 butterfly[];
};
layout(std430, set = 0, binding = 1) restrict buffer FFTBuffer {
	vec2 data[];
};
layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
};

shared vec2 row_shared[2 * MAP_SIZE];

vec2 mul_complex(in vec2 a, in vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }

#define ROW_SHARED(col, pingpong) (row_shared[(pingpong) * MAP_SIZE + (col)])
#define BUTTERFLY(col, stage)     (butterfly[(stage) * map_size + (col)])
#define DATA_IN(id, layer)  (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + 0 + (layer) * map_size * map_size + (id.y) * map_size + (id.x)])
#define DATA_OUT(id, layer) (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + NUM_SPECTRA * map_size * map_size + (layer) * map_size * map_size + (id.y) * map_size + (id.x)])
void main() {
	const uint map_size = uint(MAP_SIZE);
	const uint num_stages = findMSB(map_size);
	const uvec3 id = uvec3(gl_GlobalInvocationID.xy, cascade_index);
	const uint col = id.x;
	const uint spectrum = gl_GlobalInvocationID.z;

	ROW_SHARED(col, 0) = DATA_IN(id, spectrum);
	for (uint stage = 0U; stage < num_stages; ++stage) {
		barrier();
		uvec2 buf_idx = uvec2(stage % 2, (stage + 1) % 2);
		vec4 b = BUTTERFLY(col, stage);
		uvec2 read_indices = uvec2(floatBitsToUint(b.xy));
		vec2 upper = ROW_SHARED(read_indices[0], buf_idx[0]);
		vec2 lower = ROW_SHARED(read_indices[1], buf_idx[0]);
		ROW_SHARED(col, buf_idx[1]) = upper + mul_complex(lower, b.zw);
	}
	barrier();
	DATA_OUT(id, spectrum) = ROW_SHARED(col, num_stages % 2);
}
