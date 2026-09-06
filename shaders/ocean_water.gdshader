shader_type spatial;
render_mode world_vertex_coords, cull_disabled, specular_schlick_ggx;
// Wave Riders ocean surface. Displacement/normal maps come from ocean/WaveSim.gd (3 FFT cascades);
// the froth model follows the web game's OceanMesh.js (whitecaps on the downwind face, wind streaks,
// bubble lace, aerated brightening); lighting is Fresnel-weighted sky reflection (Godot ambient/radiance),
// GGX sun glitter, a backlit subsurface term on thin crests and the water body colour as ALBEDO.
// Keep rogue_wave() and the displacement sum in vertex() identical to shaders/ocean_compute_probe.glsl.

#define MAX_CASCADES 3

uniform sampler2DArray displacements : filter_linear, repeat_enable;
uniform sampler2DArray normals : filter_linear, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

uniform int num_cascades = 3;
uniform vec4 map_scales[MAX_CASCADES];
uniform vec4 disp_fade = vec4(6000.0, 700.0, 120.0, 0.0);
uniform vec4 normal_fade = vec4(3000.0, 400.0, 55.0, 0.0);
uniform vec4 cascade_mss = vec4(0.003, 0.006, 0.010, 0.0);
uniform float chop = 1.0;
uniform bool use_bicubic = true;
uniform vec4 rogue0 = vec4(0.0);
uniform vec4 rogue0b = vec4(0.0);
uniform vec4 rogue1 = vec4(0.0);
uniform vec4 rogue1b = vec4(0.0);

uniform vec3 water_scatter = vec3(0.05, 0.2, 0.2);
uniform vec3 water_deep = vec3(0.01, 0.05, 0.07);
uniform vec3 foam_color = vec3(0.90, 0.93, 0.96);
uniform vec2 wind_dir = vec2(0.0, 1.0);
uniform float whitecap_cov = 0.01;
uniform float foam_strength = 1.0;
uniform float whitecap = 0.6;
uniform float hs = 1.0;
uniform float time = 0.0;
uniform float base_roughness = 0.05;
uniform float shore_depth = 3.5;
uniform vec3 shore_color = vec3(0.30, 0.55, 0.50);
uniform float sss_strength = 1.0;
uniform int debug_view = 0;

varying vec2 v_uv;
varying float v_wave_y;
varying float v_conv;
varying float v_dist;
varying vec3 v_up_view;
varying float v_foam;
varying float v_fresnel;
varying float v_rough;

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

void vertex() {
	vec2 p = VERTEX.xz;
	vec2 cam = CAMERA_POSITION_WORLD.xz;
	float dist = length(p - cam);
	vec3 d = vec3(0.0);
	float conv = 0.0;
	for (int i = 0; i < num_cascades; i++) {
		vec4 sc = map_scales[i];
		float f = 1.0 - smoothstep(disp_fade[i], disp_fade[i] * 2.5, dist);
		vec4 s = texture(displacements, vec3(p * sc.xy, float(i)));
		d += vec3(s.x * chop, s.y, s.z * chop) * sc.z * f;
		conv += -s.w * f;
	}
	d += rogue_wave(p, rogue0, rogue0b);
	d += rogue_wave(p, rogue1, rogue1b);
	VERTEX += d;
	v_uv = p;
	v_wave_y = d.y;
	v_conv = conv;
	v_dist = dist;
	v_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

vec4 cubic_weights(float a) {
	float a2 = a * a;
	float a3 = a2 * a;
	float w0 = -a3 + a2 * 3.0 - a * 3.0 + 1.0;
	float w1 = a3 * 3.0 - a2 * 6.0 + 4.0;
	float w2 = -a3 * 3.0 + a2 * 3.0 + a * 3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

// Bicubic B-spline with 4 bilinear taps (GPU Gems 2, ch. 20).
vec4 texture_bicubic(sampler2DArray s, vec3 uvw) {
	vec2 dims = vec2(textureSize(s, 0).xy);
	vec2 inv = 1.0 / dims;
	uvw.xy = uvw.xy * dims + 0.5;
	vec2 fuv = fract(uvw.xy);
	vec4 wx = cubic_weights(fuv.x);
	vec4 wy = cubic_weights(fuv.y);
	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy) * inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
	return mix(
		mix(texture(s, vec3(h.yw, uvw.z)), texture(s, vec3(h.xw, uvw.z)), w.x),
		mix(texture(s, vec3(h.yz, uvw.z)), texture(s, vec3(h.xz, uvw.z)), w.x), w.y);
}

void fragment() {
	float map_size = float(textureSize(normals, 0).x);
	vec2 grad = vec2(0.0);
	float foam_acc = 0.0;
	float bubbles = 0.0;
	float mss_lost = 0.0;
	for (int i = 0; i < num_cascades; i++) {
		vec4 sc = map_scales[i];
		vec3 coords = vec3(v_uv * sc.xy, float(i));
		float f = 1.0 - smoothstep(normal_fade[i], normal_fade[i] * 2.5, v_dist);
		float ppm = map_size * sc.x;
		vec4 n;
		if (use_bicubic && ppm > 0.4 && v_dist < normal_fade[i] * 1.5) {
			n = texture_bicubic(normals, coords);
		} else {
			n = texture(normals, coords);
		}
		grad += n.xy * f;
		foam_acc = max(foam_acc, n.z * f * (i == 0 ? 0.75 : (i == 1 ? 1.0 : 0.6)));
		bubbles += n.w * f * (i == 1 ? 0.7 : 0.35);
		mss_lost += cascade_mss[i] * (1.0 - f);
	}

	// ------------------------------------------------------------- froth
	vec2 q = v_uv;
	vec2 wd = normalize(wind_dir + vec2(1e-5, 0.0));
	vec2 qs = vec2(dot(q, wd), dot(q, vec2(-wd.y, wd.x)));
	float t = time;
	vec4 fx1 = texture(foam_tex, qs * vec2(0.145 * 0.22, 0.145) - vec2(t * 0.011, t * 0.008));
	vec4 fx2 = texture(foam_tex, q * 0.62 + vec2(-t * 0.03, t * 0.021));
	vec4 fx3 = texture(foam_tex, qs * vec2(0.085, 0.50) - vec2(t * 0.016, t * 0.006));
	float covN = clamp(whitecap_cov / 0.16, 0.0, 1.0);
	float fdn = dot(grad, wd) / (length(grad) + 0.06);
	float cap_face = clamp(0.62 - 0.55 * fdn, 0.0, 1.0);
	float conv = v_conv;
	float spill_knee = mix(1.2, 0.55, smoothstep(0.0, 0.9, covN));
	float spill = smoothstep(spill_knee, spill_knee + 0.5, conv) * smoothstep(0.003, 0.02, covN);
	float fold = clamp((whitecap - (1.0 - conv)) * 3.0, 0.0, 1.0);
	float foldS = smoothstep(0.12, 0.60, fold);
	float cap_src = (foldS * 1.3 + spill * 0.85 + foam_acc * 12.0 * foam_strength) * cap_face;
	float cap_tex = fx1.r * 0.55 + fx2.r * 0.45;
	float cap_carve = cap_src * (0.40 + cap_tex * 1.15);
	float cap_on = mix(0.60, 0.34, covN);
	float cap = smoothstep(cap_on, cap_on + 0.20, cap_carve);
	float cap_core = smoothstep(cap_on + 0.28, cap_on + 0.62, cap_carve);
	float raft = smoothstep(0.02, 0.10, bubbles);
	float streak_src = (foam_acc * 10.0 + raft * 0.6) * foam_strength * smoothstep(0.02, 0.30, covN);
	float streak_pat = smoothstep(0.50, 0.80, fx3.b * 0.6 + fx3.a * 0.4);
	float streak = smoothstep(0.24, 0.55, streak_src * 1.4) * streak_pat * (0.55 + 0.45 * fx3.r);
	float raft_mask = raft * foam_strength * smoothstep(0.01, 0.20, covN);
	float lace_pat = smoothstep(0.50, 0.72, fx2.r * (0.7 + 0.5 * fx2.g) * (0.8 + 0.4 * fx3.r));
	float lace = lace_pat * raft_mask;
	float aer = clamp(foam_acc * 10.0 + raft * 0.8 + foldS * 0.5 + spill * 0.3, 0.0, 1.0) * smoothstep(0.01, 0.20, covN);
	float foam = max(cap, streak * 0.8);
	float foam_thin = max(streak, lace);

	// ------------------------------------------------------------- shore
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_lin = -vp.z / vp.w;
	float frag_lin = -VERTEX.z;
	float water_depth = max(scene_lin - frag_lin, 0.0);
	float shore = 1.0 - smoothstep(0.0, shore_depth, water_depth);
	float shore_foam = smoothstep(0.55, 1.0, shore) * smoothstep(0.35, 0.7, fx2.g * 0.6 + fx1.g * 0.4 + 0.25 * sin(time * 1.3 + v_uv.x * 0.7 + v_uv.y * 0.9) + 0.25);
	foam = max(foam, shore_foam);

	// ------------------------------------------------------------ normal
	vec3 n_world = normalize(vec3(-grad.x, 1.0, -grad.y));
	n_world = normalize(n_world + vec3(fx2.r - fx2.b, 0.0, fx2.g - fx2.a) * foam * 0.25);
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	if (!FRONT_FACING) n_view = -n_view;
	NORMAL = n_view;

	float ndv = max(dot(NORMAL, VIEW), 1e-4);
	float rough = clamp(base_roughness + 2.5 * sqrt(mss_lost), base_roughness, 0.55);
	v_fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0) * (1.0 - rough * 0.7);

	// ------------------------------------------------------------ colour
	vec3 body = water_scatter;
	body = mix(body, water_scatter * 0.5 + vec3(0.22, 0.26, 0.29), aer * 0.55);
	body += water_scatter * bubbles * 0.5;
	body = mix(body, shore_color, shore * 0.55);
	vec3 albedo = mix(body, foam_color, foam);
	albedo = mix(albedo, foam_color * 0.85, foam_thin * (1.0 - foam) * 0.55);
	ALBEDO = albedo;
	ROUGHNESS = mix(rough, 0.85, max(foam, foam_thin * 0.5));
	SPECULAR = mix(0.35, 0.22, foam);
	v_foam = foam;
	v_rough = ROUGHNESS;
	if (!FRONT_FACING) {
		ALBEDO = water_deep * 0.8;
		ROUGHNESS = 0.6;
		SPECULAR = 0.1;
	}
	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(foam_acc, bubbles, fold);
	} else if (debug_view == 2) {
		ALBEDO = vec3(0.0);
		EMISSION = n_world * 0.5 + 0.5;
	} else if (debug_view == 3) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(cap, streak, lace);
	}
}

void light() {
	vec3 L = LIGHT;
	vec3 V = VIEW;
	vec3 N = NORMAL;
	float ndl = dot(N, L);
	vec3 sun = LIGHT_COLOR * ATTENUATION;
	float up = clamp(dot(L, v_up_view), 0.0, 1.0);
	// water body: the beam entering the surface (depends on sun height, not N.L); foam: wrapped Lambert
	float body_term = (0.25 + 0.75 * up) * (1.0 - v_fresnel);
	float wrap = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	float diff = mix(body_term, wrap * 0.9, v_foam);
	// backlit subsurface scattering on thin crests facing the camera against the sun
	float bl4 = clamp(dot(L, -V), 0.0, 1.0);
	bl4 *= bl4; bl4 *= bl4;
	float bl3 = 0.5 - 0.5 * ndl;
	bl3 = bl3 * bl3 * bl3;
	float hnorm = clamp(v_wave_y / max(hs, 0.4) * 0.7 + 0.45, 0.0, 1.5);
	float sss = hnorm * bl4 * bl3 * 3.0 * sss_strength * (1.0 - v_foam);
	DIFFUSE_LIGHT += ALBEDO * sun * (vec3(diff * 1.3) + sss * vec3(0.85, 1.15, 0.9)) / PI;

	if (ndl > 0.0) {
		vec3 H = normalize(L + V);
		float ndh = max(dot(N, H), 0.0);
		float vdh = max(dot(V, H), 1e-4);
		float ndv = max(dot(N, V), 1e-4);
		float a = max(v_rough * v_rough, 0.002);
		float a2 = a * a;
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float D = a2 / (PI * dd * dd);
		float k = a * 0.5;
		float vis = 0.25 / ((ndl * (1.0 - k) + k) * (ndv * (1.0 - k) + k));
		float F = 0.02 + 0.98 * pow(1.0 - vdh, 5.0);
		SPECULAR_LIGHT += sun * D * vis * F * ndl * (1.0 - v_foam * 0.85) / PI;
	}
}
