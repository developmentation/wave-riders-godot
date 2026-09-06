shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
// Cheap procedural cloud layer on the SkyWeather dome: three noise octaves, coverage threshold,
// sun-side brightening, storm darkening, fades toward the horizon.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.3;
uniform float density = 0.5;
uniform float darkness = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color = vec3(1.0);
uniform vec3 ambient = vec3(0.6, 0.7, 0.9);
uniform vec2 wind = vec2(3.0, 0.0);
uniform float time = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * 0.00004 + wind * time * 0.00001;
	float n = texture(noise_tex, p).b * 0.58 + texture(noise_tex, p * 2.3 + 0.37).g * 0.30 + texture(noise_tex, p * 4.7 - 0.11).a * 0.12;
	float lo = 0.72 - 0.44 * coverage;
	float c = smoothstep(lo - 0.04, lo + 0.16, n);
	float thick = smoothstep(lo + 0.05, lo + 0.35, n);
	vec3 view_dir = normalize(v_world - CAMERA_POSITION_WORLD);
	float toward_sun = clamp(dot(view_dir, sun_dir), 0.0, 1.0);
	vec3 lit = vec3(1.0);
	vec3 dark = vec3(0.30, 0.32, 0.36);
	vec3 base = mix(lit, dark, darkness * 0.9);
	vec3 col = base * (ambient * 0.75 + sun_color * (0.45 + 0.35 * pow(toward_sun, 3.0)) * max(sun_dir.y * 0.8 + 0.2, 0.0));
	col *= mix(1.0, 0.55, thick * density);
	float dist = length(v_world.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(4500.0, 10500.0, dist);
	ALBEDO = col;
	ALPHA = c * fade * clamp(0.45 + density * 0.8, 0.3, 1.0);
}
