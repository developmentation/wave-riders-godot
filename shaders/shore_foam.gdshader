shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;

// Shore foam band (port of src/game/ShoreFoam.js FRAG). UV = (t across: 0 beach .. 1 sea, island
// seed); UV2 = outward shore normal (xz). Lit so a storm sky darkens the foam like everything else.
uniform float surf = 1.0;          // 1 = calm lagoon .. ~1.8 = storm surf
uniform float fade_near = 520.0;
uniform float fade_far = 720.0;

varying vec3 v_world;
varying float v_fade;
varying float v_far;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Stand-in for the engine's foam texture: r = sparse clusters, g = bubbles, a = dissolve. The
// web texture is mostly dark with bright clumps, so the channels are thresholded the same way;
// otherwise the swash carves to a solid white band.
vec4 foam_tex(vec2 p) {
	p *= 1.6;
	float n1 = vnoise(p);
	float n2 = vnoise(p * 2.13 + 7.7);
	float n3 = vnoise(p * 4.7 + 3.1);
	float clusters = smoothstep(0.50, 0.88, n1 * 0.6 + n2 * 0.4);
	float dissolve = smoothstep(0.35, 0.95, n2 * 0.5 + n3 * 0.5);
	return vec4(clusters, n3, 0.0, dissolve);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	v_fade = 1.0 - smoothstep(fade_near, fade_far, dist);
	// a 10 m band is a pixel wide at 300 m: broaden the swash with distance
	v_far = smoothstep(60.0, 350.0, dist);
}

void fragment() {
	if (v_fade < 0.01) {
		discard;
	}
	float t = UV.x;
	float seed = UV.y;
	vec2 n = UV2;
	float time = TIME;
	// along-shore phase from world position: no seam where a loop closes
	float along = v_world.x * 0.71 + v_world.z * 0.43 + seed * 13.7;

	// swash: the standing foam line, surging up and down the beach with two incommensurate periods
	float surge = sin(time * 0.75 + along * 0.045) * 0.6 + sin(time * 0.31 - along * 0.021) * 0.4;
	float line = 0.24 + surge * 0.09 * surf;
	float swash = exp(-pow((t - line) / (0.22 * surf * (1.0 + v_far)), 2.0)) * (1.1 + 0.2 * surge + 0.5 * v_far);

	// breakers: a foam pulse born at the seaward edge every ~6.5 s that runs up the shelf
	float ph = fract(time / 6.5 + along * 0.0035 + sin(along * 0.11) * 0.06 + seed * 0.37);
	float tw = mix(1.0, 0.24, ph);
	float pulse = exp(-pow((t - tw) / 0.15, 2.0)) * smoothstep(0.0, 0.35, ph) * (1.0 - smoothstep(0.72, 1.0, ph)) * (0.8 + 0.6 * surf);
	float ph2 = fract(ph + 0.5 + sin(along * 0.05) * 0.1);
	float tw2 = mix(1.0, 0.24, ph2);
	pulse += exp(-pow((t - tw2) / 0.12, 2.0)) * smoothstep(0.0, 0.35, ph2) * (1.0 - smoothstep(0.72, 1.0, ph2)) * 0.6 * surf;

	// thinning streaks of spent foam drifting seaward
	float fringe = (1.0 - smoothstep(0.30, 1.0, t)) * 0.18;
	// density_scale: the web carves with a sparse foam texture; the procedural stand-in is denser,
	// so the band is thinned here to keep the swash a line rather than a sheet
	float density = (swash * 0.7 + pulse * 0.8 + fringe) * smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.78, 1.0, t));
	if (density < 0.06) {
		discard;
	}

	// foam texture in world space, drifting shoreward (against the normal)
	vec4 fx = foam_tex(v_world.xz * 0.11 - n * time * 0.055 + vec2(time * 0.004, 0.0));
	vec4 fx2 = foam_tex(v_world.xz * 0.42 - n * time * 0.11);
	float clusters = fx.r * 0.55 + fx2.r * 0.45;
	float bubbles = fx2.g * 0.6 + fx.g * 0.4;
	float dissolve = fx.a * 0.5 + fx2.a * 0.5;

	float noise = smoothstep(0.18, 0.80, dissolve * 0.5 + clusters * 0.5);
	float carved = density * (0.30 + noise * 1.15 + 0.5 * v_far);
	float onset = 0.20 + t * 0.30;
	float foam = smoothstep(onset, onset + 0.30, carved);
	foam *= mix(0.45, 1.0, bubbles);
	if (foam < 0.004) {
		discard;
	}

	ALBEDO = vec3(0.92, 0.94, 0.95) * (1.0 + 0.12 * bubbles + 0.1 * pulse);
	ROUGHNESS = 1.0;
	ALPHA = clamp(foam, 0.0, 1.0) * 0.85 * v_fade;
}
