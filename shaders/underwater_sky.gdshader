shader_type sky;

// The "sky" seen from under water: the water column's colour at the camera's depth in every
// direction, brightened toward the ceiling (the sunlit surface / Snell's window) and darkened
// toward the bottom. Distance fog (Environment) fades everything else toward `fog_color`, so
// this is the fog at infinity.
uniform vec3 fog_color : source_color = vec3(0.09, 0.31, 0.37);
uniform vec3 ceiling_color : source_color = vec3(0.30, 0.68, 0.74);
uniform float ceiling_power = 2.5;
uniform float floor_darken = 0.55;

void sky() {
	float up = clamp(EYEDIR.y, 0.0, 1.0);
	float down = clamp(-EYEDIR.y, 0.0, 1.0);
	vec3 c = fog_color;
	c = mix(c, ceiling_color, pow(up, ceiling_power));
	c = mix(c, fog_color * floor_darken, pow(down, 1.5));
	COLOR = c;
}
