shader_type canvas_item;

// Portal white-out: an iris of warm light blooms from the centre (radius 0 -> 1), then the whole
// sheet dissolves (opacity 1 -> 0). Two expanding rings in the portal's tint ride the bloom.
uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.3);
uniform float radius = 0.0;
uniform float opacity = 1.0;
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p) / 0.95;               // 1 = the corners are covered
	// radial gradient: white core, tint band, white edge (like the web's CSS gradient)
	float g = clamp(r, 0.0, 1.0);
	vec3 col = mix(vec3(1.0), tint, smoothstep(0.28, 0.62, g) * (1.0 - smoothstep(0.62, 1.0, g)));
	float iris = 1.0 - smoothstep(radius * 1.15 - 0.06, radius * 1.15, r);
	// rings expanding with the iris
	float ring1 = exp(-pow((r - radius * 0.65) / 0.035, 2.0)) * 0.55;
	float ring2 = exp(-pow((r - radius * 1.05) / 0.02, 2.0)) * 0.35;
	col = mix(col, tint, clamp(ring1 + ring2, 0.0, 1.0) * (1.0 - iris) * step(0.001, radius) * (radius < 1.0 ? 1.0 : 0.0));
	float a = max(iris, (ring1 + ring2) * (radius < 1.0 ? 1.0 : 0.0));
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * opacity);
}
