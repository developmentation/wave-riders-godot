#[compute]
#version 450
/**
 * CPU sampling probe: evaluates the rendered surface (all cascades + rogue solitons, with the same
 * distance fades as the vertex shader) on a grid of world xz points and writes (h, dh/dx, dh/dz, 0).
 * The horizontal (choppy) displacement is inverted by fixed-point iteration so the height reported
 * for a world point is the height of the vertex column that lands there.
 * Keep total_displacement() in step with ocean_water.gdshader.
 */
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2DArray displacements;
layout(std430, set = 0, binding = 1) restrict writeonly buffer ProbeOut {
	vec4 out_data[];
};
layout(std140, set = 0, binding = 2) uniform Params {
	vec4 map_scales[4];   // 1/tile_x, 1/tile_y, displacement_scale, 0
	vec4 disp_fade;       // per-cascade displacement fade start distance (metres); w unused
	vec4 rogue0;          // origin.xz, dir.xz
	vec4 rogue0b;         // amplitude, width, lateral radius, crest travel
	vec4 rogue1;
	vec4 rogue1b;
	vec4 misc;            // chop, num_cascades, 0, 0
};
layout(push_constant) restrict readonly uniform PushConstants {
	vec2 origin;
	vec2 cam;
	float span;
	int cells;
	int out_offset;
	float eps;
};

vec3 rogue_wave(vec2 p, vec4 a, vec4 b) {
	if (b.x <= 0.001) return vec3(0.0);
	vec2 dir = a.zw;
	vec2 d = p - a.xy;
	float x = dot(d, dir) - b.w;
	float lat = dot(d, vec2(-dir.y, dir.x));
	float lat_env = exp(-lat * lat / (b.z * b.z));
	float xf = x > 0.0 ? x * 1.6 : x;
	float s = 1.0 / cosh(clamp(xf / b.y, -12.0, 12.0));
	float tr = 1.0 / cosh(clamp((x - b.y * 1.6) / (b.y * 1.1), -12.0, 12.0));
	float prof = s * s - 0.16 * tr * tr;
	float top = s * s;
	vec2 push = dir * (top * top * min(b.x, b.y * 0.4) * 0.3 * lat_env);
	return vec3(push.x, b.x * prof * lat_env, push.y);
}

vec3 total_displacement(vec2 p) {
	float dist = length(p - cam);
	vec3 d = vec3(0.0);
	int n = int(misc.y);
	for (int i = 0; i < n; ++i) {
		vec4 sc = map_scales[i];
		float f = 1.0 - smoothstep(disp_fade[i], disp_fade[i] * 2.5, dist);
		vec4 s = texture(displacements, vec3(p * sc.xy, float(i)));
		d += vec3(s.x * misc.x, s.y, s.z * misc.x) * sc.z * f;
	}
	d += rogue_wave(p, rogue0, rogue0b);
	d += rogue_wave(p, rogue1, rogue1b);
	return d;
}

float surface_height(vec2 world) {
	vec2 q = world;
	vec3 d = vec3(0.0);
	for (int i = 0; i < 3; ++i) {
		d = total_displacement(q);
		q = world - d.xz;
	}
	return d.y;
}

void main() {
	uint idx = gl_GlobalInvocationID.x;
	uint n = uint(cells * cells);
	if (idx >= n) return;
	uint ix = idx % uint(cells), iz = idx / uint(cells);
	vec2 p = origin + vec2(float(ix), float(iz)) * (span / float(cells - 1));
	float h = surface_height(p);
	float hx = surface_height(p + vec2(eps, 0.0));
	float hz = surface_height(p + vec2(0.0, eps));
	out_data[uint(out_offset) + idx] = vec4(h, (hx - h) / eps, (hz - h) / eps, 0.0);
}
