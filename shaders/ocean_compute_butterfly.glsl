#[compute]
#version 450
/** Butterfly factors for the Stockham FFT (one row per stage). */
#define PI (3.141592653589793)
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict writeonly buffer ButterflyBuffer {
	vec4 butterfly[];
};

vec2 exp_complex(in float x) { return vec2(cos(x), sin(x)); }

#define BUTTERFLY(col, stage) (butterfly[(stage) * map_size + (col)])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x * 2;
	const uint col = gl_GlobalInvocationID.x;
	const uint stage = gl_GlobalInvocationID.y;
	uint stride = 1 << stage, mid = map_size >> (stage + 1);
	uint i = col >> stage, j = col % stride;
	vec2 twiddle = exp_complex(PI / float(stride) * float(j));
	uint r0 = stride * (i + 0) + j, r1 = stride * (i + mid) + j;
	uint w0 = stride * (2 * i + 0) + j, w1 = stride * (2 * i + 1) + j;
	vec2 read_indices = vec2(uintBitsToFloat(r0), uintBitsToFloat(r1));
	BUTTERFLY(w0, stage) = vec4(read_indices, twiddle);
	BUTTERFLY(w1, stage) = vec4(read_indices, -twiddle);
}
