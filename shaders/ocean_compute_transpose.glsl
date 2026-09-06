#[compute]
#version 450
/** Coalesced tile transpose (output half -> input half of the FFT buffer). */
#define TILE_SIZE   (32U)
#define NUM_SPECTRA (4U)
layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer ButterflyBuffer {
	vec4 butterfly[];
};
layout(std430, set = 0, binding = 1) restrict buffer FFTBuffer {
	vec2 data[];
};
layout(std140, set = 0, binding = 2) uniform CascadeParams {
	vec4 tile_depth_time[3];
	vec4 foam_a[3];
	vec4 foam_b[3];            // .w > 0.5 = skip this cascade this frame
};

shared vec2 tile[TILE_SIZE][TILE_SIZE + 1];

#define DATA_IN(id, layer)  (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + NUM_SPECTRA * map_size * map_size + (layer) * map_size * map_size + (id.y) * map_size + (id.x)])
#define DATA_OUT(id, layer) (data[(id.z) * map_size * map_size * NUM_SPECTRA * 2 + 0 + (layer) * map_size * map_size + (id.y) * map_size + (id.x)])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const uvec2 id_block = gl_WorkGroupID.xy;
	const uvec2 id_local = gl_LocalInvocationID.xy;
	const uint cascade_index = gl_WorkGroupID.z / NUM_SPECTRA;
	const uint spectrum = gl_WorkGroupID.z % NUM_SPECTRA;
	if (foam_b[cascade_index].w > 0.5) return;
	uvec3 id = uvec3(gl_GlobalInvocationID.xy, cascade_index);
	tile[id_local.y][id_local.x] = DATA_IN(id, spectrum);
	barrier();
	id.xy = id_block.yx * TILE_SIZE + id_local.xy;
	DATA_OUT(id, spectrum) = tile[id_local.x][id_local.y];
}
