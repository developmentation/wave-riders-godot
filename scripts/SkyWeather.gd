class_name SkyWeather
extends Node3D
## Sky, sun, fog, clouds, rain and lightning for Wave Riders, driven by Ocean's blended weather.
## It is the "SkyWeather" child of ocean/Ocean.tscn: Ocean finds it by name, calls apply_quality(preset)
## from set_quality() and apply_weather(w, hs, immediate) every frame (weather crossfades happen in
## Ocean, so this node just applies whatever it is given). It can also live elsewhere in the tree and be
## driven by hand with the same two calls. Builds its own WorldEnvironment (PhysicalSkyMaterial),
## DirectionalLight3D sun + dim fill, a flash light + bolt mesh for lightning, camera-following rain
## (GPUParticles3D) and a procedural cloud dome (shaders/ocean_clouds.gdshader).

signal lightning_flash(strength: float)

var environment: Environment
var sky: Sky
var sky_material: PhysicalSkyMaterial
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var flash: DirectionalLight3D
var rain: GPUParticles3D
var rain_material: ParticleProcessMaterial
var clouds: MeshInstance3D
var cloud_mat: ShaderMaterial
var bolt: MeshInstance3D
var bolt_mesh: ImmediateMesh
var preset: Dictionary = Quality.get_preset("medium")
## Unit vector from the scene toward the sun (world space).
var sun_vector := Vector3(0.3, 0.7, 0.3).normalized()
var sun_color := Color.WHITE
var storminess := 0.0

var _w: Dictionary = {}
var _lightning_timer := 3.0
var _flash_age := 99.0
var _flash_strength := 0.0
var _base_sky_energy := 1.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _has_noise := false
var _night_tex: ImageTexture


func _ready() -> void:
	_rng.seed = 7
	# --- environment
	environment = Environment.new()
	sky_material = PhysicalSkyMaterial.new()
	sky_material.use_debanding = true
	sky_material.sun_disk_scale = 1.6
	sky = Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256  # realtime skies require 256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 8.0
	sky_material.rayleigh_color = Color(0.20, 0.38, 0.66)
	_night_tex = _make_night_sky()
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0005
	environment.fog_aerial_perspective = 0.5
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.03
	environment.glow_hdr_threshold = 1.3
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.volumetric_fog_enabled = false
	environment.volumetric_fog_density = 0.01
	environment.volumetric_fog_length = 400.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = environment
	add_child(we)

	# --- lights
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 2.0
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.0
	fill.light_color = Color(0.55, 0.65, 0.95)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-55.0, 140.0, 0.0)
	add_child(fill)
	flash = DirectionalLight3D.new()
	flash.name = "Flash"
	flash.light_energy = 0.0
	flash.light_color = Color(0.85, 0.9, 1.0)
	flash.shadow_enabled = false
	flash.rotation_degrees = Vector3(-70.0, 30.0, 0.0)
	flash.visible = false
	add_child(flash)

	# --- rain
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain_material = ParticleProcessMaterial.new()
	rain_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_material.emission_box_extents = Vector3(18.0, 2.0, 18.0)
	rain_material.direction = Vector3(0.0, -1.0, 0.0)
	rain_material.spread = 2.0
	rain_material.initial_velocity_min = 14.0
	rain_material.initial_velocity_max = 19.0
	rain_material.gravity = Vector3(0.0, -6.0, 0.0)
	rain_material.scale_min = 0.6
	rain_material.scale_max = 1.0
	rain.process_material = rain_material
	rain.amount = int(preset.rain)
	rain.lifetime = 1.1
	rain.preprocess = 1.0
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	rain.emitting = false
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.4)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.albedo_color = Color(0.78, 0.84, 0.94, 0.32)
	drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	drop_mat.distance_fade_min_distance = 2.0
	drop_mat.distance_fade_max_distance = 4.5
	drop.material = drop_mat
	rain.draw_pass_1 = drop
	add_child(rain)

	# --- clouds
	clouds = MeshInstance3D.new()
	clouds.name = "Clouds"
	clouds.mesh = _build_cloud_dome()
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://shaders/ocean_clouds.gdshader")
	clouds.material_override = cloud_mat
	clouds.visible = false
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.custom_aabb = AABB(Vector3(-40000, -100, -40000), Vector3(80000, 3000, 80000))
	add_child(clouds)

	# --- lightning bolt
	bolt_mesh = ImmediateMesh.new()
	bolt = MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.mesh = bolt_mesh
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.9, 0.93, 1.0)
	bm.emission_enabled = true
	bm.emission = Color(0.8, 0.85, 1.0)
	bm.emission_energy_multiplier = 6.0
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bolt.material_override = bm
	bolt.custom_aabb = AABB(Vector3(-3000, -10, -3000), Vector3(6000, 1500, 6000))
	bolt.visible = false
	add_child(bolt)
	apply_quality(preset)


## RGBA noise (seamless) used by the cloud layer; Ocean shares its foam noise. Clouds stay hidden until set.
func set_noise_texture(tex: Texture2D) -> void:
	cloud_mat.set_shader_parameter("noise_tex", tex)
	_has_noise = true
	clouds.visible = bool(preset.clouds)


func apply_quality(p: Dictionary) -> void:
	preset = p
	var shadows := int(p.shadows)
	sun.shadow_enabled = shadows > 0
	if shadows >= 4:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 300.0
	elif shadows >= 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 200.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 120.0
	if shadows >= 4:
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	elif shadows >= 2:
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	else:
		RenderingServer.directional_shadow_atlas_set_size(2048 if shadows > 0 else 1024, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	environment.ssr_enabled = bool(p.ssr)
	environment.ssr_max_steps = 48
	environment.sdfgi_enabled = bool(p.sdfgi)
	environment.glow_enabled = bool(p.glow)
	clouds.visible = bool(p.clouds) and _has_noise
	if rain.amount != int(p.rain):
		rain.amount = int(p.rain)
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if bool(p.get("sky_realtime", true)) else Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256 if bool(p.get("sky_realtime", true)) else Sky.RADIANCE_SIZE_128


## Applies a (blended) weather dictionary. Called by Ocean every frame.
func apply_weather(w: Dictionary, hs: float, immediate := false) -> void:
	_w = w
	var elev := deg_to_rad(float(w.get("sun_elev_deg", 40.0)))
	var az := deg_to_rad(float(w.get("sun_azimuth_deg", 110.0)))
	var cover := clampf(float(w.get("cloud_cover", 0.2)), 0.0, 1.0)
	var rain_amt := clampf(float(w.get("rain", 0.0)), 0.0, 1.0)
	var fog := clampf(float(w.get("fog", 0.0)), 0.0, 1.0)
	var rate := maxf(float(w.get("lightning_rate", 0.0)), 0.0)
	storminess = clampf(cover * 1.1 - 0.25 + rain_amt * 0.5 + fog * 0.3, 0.0, 1.0)

	# sun
	sun_vector = Vector3(cos(elev) * sin(az), sin(elev), cos(elev) * cos(az)).normalized()
	var up := Vector3.UP if absf(sun_vector.y) < 0.98 else Vector3.BACK
	sun.global_transform = Transform3D(Basis.looking_at(-sun_vector, up), Vector3.ZERO)
	var warm := Color(1.0, 0.48, 0.22).lerp(Color(1.0, 0.97, 0.92), smoothstep(-0.02, 0.35, sin(elev)))
	sun_color = warm.lerp(Color(0.75, 0.78, 0.85), storminess * 0.8)
	sun.light_color = sun_color
	var sun_up := clampf(sin(elev), 0.0, 1.0)
	sun.light_energy = pow(sun_up, 0.4) * 3.0 * (1.0 - 0.5 * cover * cover) * (1.0 - 0.4 * fog)
	fill.light_energy = lerpf(0.05, 0.6, 1.0 - sun_up) * (0.3 + 0.7 * storminess) + 0.45 * clampf(-sin(elev) * 8.0, 0.0, 1.0)
	fill.visible = fill.light_energy > 0.08   # every directional light costs a full light() pass on the water
	sun.visible = sun.light_energy > 0.01

	# sky
	# storms: grey out the physical sky (no sunset glow), which also greys the ambient and the reflections
	sky_material.turbidity = 1.2 + (12.0 * fog + 5.0 * cover * cover) * (1.0 - 0.8 * storminess)
	sky_material.mie_coefficient = 0.003 + (0.02 * fog + 0.008 * cover) * (1.0 - 0.8 * storminess)
	sky_material.mie_eccentricity = 0.8 - 0.5 * storminess
	sky_material.mie_color = Color(0.64, 0.72, 0.86).lerp(Color(0.55, 0.57, 0.62), storminess)
	sky_material.rayleigh_coefficient = 4.4 + 1.0 * storminess
	sky_material.rayleigh_color = Color(0.16, 0.34, 0.70).lerp(Color(0.42, 0.44, 0.50), storminess)
	sky_material.sun_disk_scale = 1.6 * (1.0 - storminess)
	# a physical sky is dim at low sun; lift it so golden hour reads bright, not gloomy (not below the horizon)
	var dusk_boost := 1.0 + 1.2 * (1.0 - smoothstep(0.0, 0.45, sin(elev))) * smoothstep(-0.05, 0.05, sin(elev))
	_base_sky_energy = lerpf(1.0, 0.4, pow(storminess, 1.3)) * dusk_boost
	var want_night: Texture2D = _night_tex if elev < deg_to_rad(4.0) else null
	if sky_material.night_sky != want_night:
		sky_material.night_sky = want_night
	sky_material.energy_multiplier = _base_sky_energy
	var horizon := Color(0.58, 0.72, 0.90).lerp(Color(0.20, 0.22, 0.28), storminess)
	horizon = horizon.lerp(Color(0.10, 0.12, 0.18), clampf(-sin(elev) * 6.0, 0.0, 1.0))
	sky_material.ground_color = horizon * 0.5

	# fog: distance haze always, grey murk in storms
	environment.fog_density = 0.0004 + 0.011 * fog + 0.0015 * rain_amt
	environment.fog_light_color = horizon
	environment.fog_light_energy = lerpf(1.0, 0.6, storminess)
	environment.fog_sky_affect = storminess * 0.9
	environment.fog_sun_scatter = 0.25 * (1.0 - storminess)
	environment.fog_aerial_perspective = 0.5
	environment.tonemap_exposure = 1.0 - 0.2 * storminess
	environment.volumetric_fog_enabled = bool(preset.volumetric) and (fog > 0.25 or rain_amt > 0.3)
	environment.volumetric_fog_density = 0.004 + 0.02 * fog
	environment.volumetric_fog_albedo = horizon.lightened(0.2)
	environment.ambient_light_energy = lerpf(1.0, 1.4, storminess)

	# rain
	rain.emitting = rain_amt > 0.04
	rain.amount_ratio = clampf(rain_amt, 0.05, 1.0)
	var wdir := deg_to_rad(float(w.get("wind_dir_deg", 0.0)))
	var wind := Vector2(sin(wdir), cos(wdir)) * clampf(float(w.get("wind_speed", 5.0)) * 0.04, 0.0, 0.8)
	rain_material.direction = Vector3(wind.x, -1.0, wind.y).normalized()
	rain_material.gravity = Vector3(wind.x * 4.0, -6.0, wind.y * 4.0)

	# clouds
	if cloud_mat:
		cloud_mat.set_shader_parameter("coverage", cover)
		cloud_mat.set_shader_parameter("density", clampf(0.35 + 0.6 * storminess + 0.3 * rain_amt, 0.0, 1.0))
		cloud_mat.set_shader_parameter("darkness", storminess)
		cloud_mat.set_shader_parameter("sun_dir", sun_vector)
		cloud_mat.set_shader_parameter("sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b) * clampf(sun.light_energy * 0.6 + 0.2, 0.0, 1.5))
		cloud_mat.set_shader_parameter("ambient", Vector3(horizon.r, horizon.g, horizon.b) * lerpf(1.2, 0.5, storminess))
		cloud_mat.set_shader_parameter("wind", Vector2(sin(wdir), cos(wdir)) * float(w.get("wind_speed", 5.0)))

	# lightning cadence
	if rate <= 0.001:
		_lightning_timer = 2.0
	elif immediate:
		_lightning_timer = 1.5


func _process(dt: float) -> void:
	_time += dt
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var fwd := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	rain.global_position = cam_pos + Vector3(0.0, 11.0, 0.0) + Vector3(fwd.x, 0.0, fwd.z) * 7.0
	clouds.global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)
	if cloud_mat:
		cloud_mat.set_shader_parameter("time", _time)

	var rate := maxf(float(_w.get("lightning_rate", 0.0)), 0.0)
	if rate > 0.001:
		_lightning_timer -= dt
		if _lightning_timer <= 0.0:
			_lightning_timer = _rng.randf_range(0.45, 1.6) * 6.0 / rate
			_strike(cam_pos, fwd)

	if _flash_age < 0.6:
		_flash_age += dt
		var e := maxf(0.0, 1.0 - _flash_age / 0.4)
		var flick := 0.55 + 0.45 * pow(sin(_flash_age * 62.0), 2.0)
		flash.light_energy = _flash_strength * 6.0 * e * flick
		sky_material.energy_multiplier = _base_sky_energy * (1.0 + _flash_strength * 1.6 * e * flick)
		bolt.visible = _flash_age < 0.16
		flash.visible = true
	elif flash.light_energy != 0.0:
		flash.light_energy = 0.0
		flash.visible = false
		sky_material.energy_multiplier = _base_sky_energy
		bolt.visible = false


func _strike(cam_pos: Vector3, fwd: Vector3) -> void:
	_flash_strength = _rng.randf_range(0.6, 1.4)
	_flash_age = 0.0
	var ang := _rng.randf_range(-1.1, 1.1)
	var dist := _rng.randf_range(250.0, 1100.0)
	var dir2 := Vector2(fwd.x, fwd.z).normalized().rotated(ang)
	var base := Vector3(cam_pos.x + dir2.x * dist, 0.0, cam_pos.z + dir2.y * dist)
	flash.rotation_degrees = Vector3(-65.0, rad_to_deg(atan2(dir2.x, dir2.y)) + 180.0, 0.0)
	_build_bolt(base, cam_pos)
	lightning_flash.emit(_flash_strength * clampf(1.0 - dist / 1600.0, 0.2, 1.0))


func _build_bolt(base: Vector3, cam_pos: Vector3) -> void:
	bolt_mesh.clear_surfaces()
	bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var to_cam := (cam_pos - base)
	to_cam.y = 0.0
	var right := to_cam.normalized().cross(Vector3.UP).normalized()
	var top := base + Vector3(_rng.randf_range(-60.0, 60.0), 620.0, _rng.randf_range(-60.0, 60.0))
	var segs := 14
	var prev := top
	for i in range(1, segs + 1):
		var f := float(i) / float(segs)
		var p := top.lerp(base, f) + Vector3(_rng.randf_range(-70.0, 70.0), _rng.randf_range(-12.0, 12.0), _rng.randf_range(-70.0, 70.0)) * (1.0 - f * 0.6)
		if i == segs:
			p = base
		var w0 := lerpf(3.2, 1.2, float(i - 1) / float(segs))
		var w1 := lerpf(3.2, 1.2, f)
		bolt_mesh.surface_add_vertex(prev - right * w0)
		bolt_mesh.surface_add_vertex(prev + right * w0)
		bolt_mesh.surface_add_vertex(p + right * w1)
		bolt_mesh.surface_add_vertex(prev - right * w0)
		bolt_mesh.surface_add_vertex(p + right * w1)
		bolt_mesh.surface_add_vertex(p - right * w1)
		prev = p
	bolt_mesh.surface_end()
	bolt.global_position = Vector3.ZERO


## Dim grey gradient added by PhysicalSkyMaterial when the sun is below the horizon, so a night storm
## still has a readable (and reflectable) sky instead of pure black.
static func _make_night_sky() -> ImageTexture:
	var img := Image.create(4, 16, false, Image.FORMAT_RGBF)
	for y in 16:
		var f := float(y) / 15.0   # 0 = top of the sky, 1 = nadir
		var horizon := 1.0 - absf(f - 0.5) * 2.0
		var lum := 0.03 + 0.09 * pow(horizon, 2.0)
		for x in 4:
			img.set_pixel(x, y, Color(lum * 0.85, lum * 0.9, lum * 1.1))
	return ImageTexture.create_from_image(img)


## Cloud dome: a curved disc ~1.4 km up that bends down to the horizon at ~9 km.
static func _build_cloud_dome() -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var segments := 48
	var radii := PackedFloat32Array()
	var r := 150.0
	while r < 14000.0:
		radii.append(r)
		r *= 1.32
	verts.append(Vector3(0.0, 1400.0, 0.0))
	for ri in radii.size():
		var rad := radii[ri]
		var y := 1400.0 - rad * rad / (2.0 * 90000.0)   # ~300 m up at 14 km, never below the sea
		for s in segments:
			var a := TAU * float(s) / float(segments)
			verts.append(Vector3(cos(a) * rad, y, sin(a) * rad))
	for s in segments:
		idx.append(0)
		idx.append(1 + s)
		idx.append(1 + (s + 1) % segments)
	for ri in range(radii.size() - 1):
		var b0 := 1 + ri * segments
		var b1 := b0 + segments
		for s in segments:
			var s1 := (s + 1) % segments
			idx.append(b0 + s)
			idx.append(b1 + s)
			idx.append(b1 + s1)
			idx.append(b0 + s)
			idx.append(b1 + s1)
			idx.append(b0 + s1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
