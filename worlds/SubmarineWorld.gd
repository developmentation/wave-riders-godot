class_name SubmarineWorld
extends Node3D
## The Deep Run — port of the web game's src/game/SubmarineWorld.js (buildSubWorld + setSubmerged).
## Same surface as worlds/World.gd: build(id), def, height_at(x, z), terrain_at(x, z), update(dt,
## camera), dispose(); plus `underwater = true`, `seabed` (the analytic DeepSeabed shared with every
## SubPhysics.ground_fn) and set_submerged(on, depth, camera).
##
## Underwater look: set_submerged() overrides the camera's Environment (Camera3D.environment) with
## an underwater one — water-coloured sky shader with a brightened ceiling, exponential distance fog
## whose colour follows the camera's depth (turquoise -> deep blue), flat ambient, the surface
## environment's tonemap/glow kept. Main.gd calls it every frame with the camera's depth below
## ocean.height_at; it is cheap (a few property sets, no environment swap unless the state flips).

var def: Dictionary
var underwater := true
var seabed: DeepSeabed
var triangles := 0
var kelp_strands := 0
var build_ms := 0
## The Environment used while submerged (built lazily from the world's surface environment).
var underwater_environment: Environment
var submerged := false

var _tiles: Array = []          # [{node, cx, cz}]
var _seabed_mat: ShaderMaterial
var _kelp_mat: ShaderMaterial
var _snow_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _snow: GPUParticles3D
var _details: MeshInstance3D
var _kelp: MultiMeshInstance3D
var _camera: Camera3D
var _fog_color := Color(0.09, 0.31, 0.37)
var _fog_density := 0.022
var _absorb := Vector3(0.045, 0.015, 0.006)
var _last_depth := -1.0
## The web's fog colour is the fraction of the *sky* irradiance the water column glows with; this
## is that sky light (linear) — bluish and well under white — so the column reads mid-blue, not milk.
@export var sky_irradiance := Color(0.34, 0.45, 0.64)


func build(id: String) -> void:
	if id != "deep":
		push_error("SubmarineWorld: unknown submarine world '%s'" % id)
		return
	var t0 := Time.get_ticks_msec()
	seabed = DeepSeabed.new()
	def = seabed.def
	var fog: Dictionary = def.fog
	_fog_color = Color(fog.color[0], fog.color[1], fog.color[2])
	_fog_density = fog.density
	_absorb = Vector3(fog.absorb[0], fog.absorb[1], fog.absorb[2])

	_seabed_mat = ShaderMaterial.new()
	_seabed_mat.shader = load("res://shaders/underwater_seabed.gdshader")
	_seabed_mat.set_shader_parameter("absorb", _absorb)
	_kelp_mat = ShaderMaterial.new()
	_kelp_mat.shader = load("res://shaders/underwater_kelp.gdshader")
	_kelp_mat.set_shader_parameter("absorb", _absorb)
	_kelp_mat.set_shader_parameter("wave", 0.9)
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = load("res://shaders/underwater_snow.gdshader")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7331

	# ---- seabed tiles: fine along the course, coarse out on the plain
	var soup := DeepMesh.new()
	var X0 := -500.0
	var X1 := 500.0
	var Z0 := -350.0
	var Z1 := 950.0
	var z0 := Z0
	while z0 < Z1:
		var x0 := X0
		while x0 < X1:
			var cx := x0 + DeepMesh.TILE / 2.0
			var cz := z0 + DeepMesh.TILE / 2.0
			var d := DeepSeabed.dist_to_path(cx, cz)
			var cells := 16 if d < 150.0 else (8 if d < 320.0 else 4)   # 6.25 m cells along the course, 12.5 m nearby, 25 m out on the plain
			soup.clear()
			soup.build_tile(seabed, x0, z0, cells)
			var mi := MeshInstance3D.new()
			mi.name = "seabed_%d_%d" % [int(x0), int(z0)]
			mi.mesh = soup.to_mesh(_seabed_mat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_tiles.append({"node": mi, "cx": cx, "cz": cz})
			triangles += soup.triangles()
			x0 += DeepMesh.TILE
		z0 += DeepMesh.TILE

	# ---- rock details: pillars, the wreck pile, two arches over the canyon
	soup.clear()
	for i in DeepSeabed.PILLARS.size():
		soup.add_pillar(seabed, i, rng)
	soup.add_wreck(seabed, rng)
	soup.add_arch(seabed, 0.40, rng)
	soup.add_arch(seabed, 0.66, rng)
	_details = MeshInstance3D.new()
	_details.name = "seabed_details"
	_details.mesh = soup.to_mesh(_seabed_mat)
	add_child(_details)
	triangles += soup.triangles()

	# ---- kelp (MultiMesh, swayed in the vertex shader)
	var mm := DeepMesh.build_kelp(seabed, rng, 280, _kelp_mat)
	_kelp = MultiMeshInstance3D.new()
	_kelp.name = "kelp"
	_kelp.multimesh = mm
	_kelp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_kelp)
	kelp_strands = mm.instance_count
	triangles += kelp_strands * 12

	# ---- marine snow around the camera (visible only while submerged)
	_snow = DeepMesh.build_snow(_snow_mat, 520)
	_snow.visible = false
	_snow.emitting = false
	add_child(_snow)

	build_ms = Time.get_ticks_msec() - t0
	var clearances := PackedStringArray()
	for g in def.gates:
		clearances.append("%.1f" % (g.y - g.width / 2.0 - height_at(g.x, g.z)))
	print("[SubmarineWorld] deep: %d triangles (%d tiles, %d kelp), %d hoops, built in %d ms, hoop clearance m: %s" % [
		triangles, _tiles.size(), kelp_strands, def.gates.size(), build_ms, " ".join(clearances)])


## Seabed height (m, negative) at world (x, z). Exact for the mesh's own source function.
func height_at(x: float, z: float) -> float:
	return seabed.height_at(x, z)


func terrain_at(x: float, z: float) -> float:
	return seabed.height_at(x, z)


## Per frame: distance-cull the tiles the fog hides, keep the snow box on the camera.
func update(_dt: float, camera: Camera3D) -> void:
	if camera == null:
		return
	var cp := camera.global_position
	# Nothing is visible past ~4 visibility lengths (exp(-0.022 * (260 - 71)) ~ 1.5% at a tile's near corner).
	var cut := 260.0 if submerged else 420.0
	var cut2 := cut * cut
	for t in _tiles:
		var dx: float = t.cx - cp.x
		var dz: float = t.cz - cp.z
		t.node.visible = dx * dx + dz * dz < cut2
	if _snow.visible:
		_snow.global_position = cp


## Toggle the underwater look for `camera` (default: the viewport's current camera). `depth` is
## the camera's depth below the sea surface in metres and tints the fog (turquoise -> deep blue).
func set_submerged(on: bool, depth := 0.0, camera: Camera3D = null) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	if underwater_environment == null:
		_build_environment(camera)
	if on != submerged or camera != _camera:
		if _camera != null and _camera != camera and _camera.environment == underwater_environment:
			_camera.environment = null
		_camera = camera
		camera.environment = underwater_environment if on else null
		submerged = on
		_snow.visible = on
		_snow.emitting = on
		if on:
			_snow.global_position = camera.global_position
			_snow.restart()
		_last_depth = -1.0
	if on and absf(depth - _last_depth) > 0.05:
		_last_depth = depth
		var d := maxf(depth, 0.0)
		var att := Vector3(exp(-_absorb.x * d), exp(-_absorb.y * d), exp(-_absorb.z * d))
		var base := _fog_color * sky_irradiance
		var c := Color(base.r * att.x, base.g * att.y, base.b * att.z)
		# keep the water column readable at depth: normalise toward a floor of brightness
		var lum := c.r * 0.3 + c.g * 0.5 + c.b * 0.2
		var floor_lum := 0.03
		if lum < floor_lum and lum > 0.0:
			c = c * (floor_lum / lum)
		# Environment colours and `source_color` uniforms are sRGB-encoded; the web values are linear.
		var cs := c.linear_to_srgb()
		underwater_environment.fog_light_color = cs
		underwater_environment.ambient_light_color = cs
		underwater_environment.ambient_light_energy = 1.0
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("fog_color", cs)
			var ceil := Color(base.r * 2.6, base.g * 2.3, base.b * 2.0) * lerpf(1.0, 0.35, smoothstep(0.0, 45.0, d))
			_sky_mat.set_shader_parameter("ceiling_color", ceil.linear_to_srgb())
		_snow_mat.set_shader_parameter("tint", (c * 2.4).linear_to_srgb())


func _build_environment(camera: Camera3D) -> void:
	var base: Environment = camera.environment
	if base == null and camera.get_world_3d() != null:
		base = camera.get_world_3d().environment
	var env: Environment = base.duplicate() if base != null else Environment.new()
	if base == null:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
		env.glow_enabled = true
		env.glow_intensity = 0.4
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/underwater_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = (_fog_color * sky_irradiance).linear_to_srgb()
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = (_fog_color * sky_irradiance).linear_to_srgb()
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = _fog_density
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.fog_height_density = 0.0
	env.volumetric_fog_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	underwater_environment = env


func dispose() -> void:
	if _camera != null and is_instance_valid(_camera) and _camera.environment == underwater_environment:
		_camera.environment = null
	_camera = null
	submerged = false
	for t in _tiles:
		t.node.queue_free()
	_tiles.clear()
	queue_free()


func _exit_tree() -> void:
	if _camera != null and is_instance_valid(_camera) and _camera.environment == underwater_environment:
		_camera.environment = null
