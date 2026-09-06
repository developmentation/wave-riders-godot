class_name Ocean
extends Node3D
## FFT ocean for Wave Riders: three JONSWAP/TMA + swell cascades simulated on the GPU
## (ocean/WaveSim.gd, compute shaders in shaders/ocean_compute_*.glsl), a camera-following
## clipmap mesh shaded by shaders/ocean_water.gdshader, weather crossfades that also drive the
## SkyWeather child (sun, sky, fog, rain, lightning), rogue-wave solitons, and CPU-side height
## sampling read back from a GPU probe pass (64x64 coarse grid ~200 m + 40x40 fine grid ~30 m
## around the focus, one to three frames of latency, bilinear on the CPU, two frames kept for dh/dt).
##
## Contract (docs/GODOT-PORT.md): set_weather(w, immediate), sample(x, z) -> Vector3(h, dh/dx, dh/dz),
## height_at, surface_velocity_y, set_focus, set_quality, significant_wave_height, signal weather_changed.

signal weather_changed
signal lightning(strength: float)

const BLEND_SECONDS := 2.0
const FETCH_KM := 150.0
const DEPTH := 300.0
const G := 9.81
const TILE_LENGTHS_3 := [2400.0, 300.0, 40.0]
const TILE_LENGTHS_2 := [1200.0, 100.0]
## Displacement fade start per cascade (m); full fade at 2.5x. The long cascade stops before the outer clipmap
## rings (150 m+ cells) would alias a 300-400 m swell into a stepped horizon.
const DISP_FADE_3 := [2500.0, 700.0, 120.0]
const DISP_FADE_2 := [2000.0, 200.0]
const COARSE_CELLS := 64
const FINE_CELLS := 40
const FINE_SPAN := 30.0

const DEFAULT_WEATHER := {
	"wind_speed": 5.0, "wind_dir_deg": 20.0, "swell_hs": 0.8, "swell_period": 9.0, "choppiness": 1.0,
	"foam": 0.4, "water_color": Color(0.16, 0.36, 0.42), "water_deep": Color(0.07, 0.17, 0.24),
	"sun_elev_deg": 40.0, "sun_azimuth_deg": 110.0, "cloud_cover": 0.2, "rain": 0.0, "fog": 0.0, "lightning_rate": 0.0,
}

## Significant wave height (m) integrated from the simulated spectrum (band-limited to what the cascades carry).
var significant_wave_height := 0.8
## 4 x the standard deviation of the coarse probe grid, smoothed; a sanity check on the value above.
var measured_wave_height := 0.0
var quality := "medium"
var weather: Dictionary = DEFAULT_WEATHER.duplicate()
var time_scale := 1.0
## Perf A/B switches for tests: {"skip_sim": bool, "skip_probe": bool}
var debug_flags := {}
var probe_span := 200.0:
	set(v):
		probe_span = clampf(v, 60.0, 600.0)
## Debug view for the water shader: 0 off, 1 foam channels, 2 normals.
var debug_view := 0:
	set(v):
		debug_view = v
		if _mat:
			_mat.set_shader_parameter("debug_view", v)

var _sim := OceanWaveSim.new()
var _surface: MeshInstance3D
var _mat: ShaderMaterial
var _noise_tex: ImageTexture
var _disp_tex := Texture2DArrayRD.new()
var _norm_tex := Texture2DArrayRD.new()
var _sky: Node = null
var _preset: Dictionary = Quality.get_preset("medium")
var _time := 0.0
var _from: Dictionary = {}
var _target: Dictionary = {}
var _blend_t := 1.0
var _spectrum_dirty := true
var _tiles: Array = TILE_LENGTHS_3
var _cascade_count := 3
var _map_scales := PackedVector4Array()
var _disp_fade := Vector4.ZERO
var _normal_fade := Vector4.ZERO
var _k_hi := PackedFloat32Array()
var _spec := {}
var _focus := Vector2.ZERO
var _focus_set := false
var _camera_xz := Vector2.ZERO
var _camera_pos := Vector3(0, 6, 0)
var _snap := 1.2
var _sim_ok := false

# probe / sampling state
var _grids: Array = []
var _cur := {"valid": false}
var _prev := {"valid": false}
var _arrived: Array = []
var _arrived_mutex := Mutex.new()
var _inflight := 0
var _readbacks := 0
var _fallbacks := 0
var _dropped := 0
var _frame := 0
var _cascade_last_time := [0.0, 0.0, 0.0]
var last_dhdt := 0.0
var _tmp := Vector3.ZERO

# rogue waves: [origin(Vector2), dir(Vector2), amp, width, lateral, t0, speed, alive]
var _rogues: Array = []


func _ready() -> void:
	process_priority = -50
	add_to_group("harness_state")
	_sky = get_node_or_null("SkyWeather")
	if _sky and _sky.has_signal("lightning_flash"):
		_sky.lightning_flash.connect(func(s: float): lightning.emit(s))
	_grids = [
		{"cells": COARSE_CELLS, "span": probe_span, "offset": 0},
		{"cells": FINE_CELLS, "span": FINE_SPAN, "offset": COARSE_CELLS * COARSE_CELLS},
	]
	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ocean_water.gdshader")
	_noise_tex = _make_noise_texture()
	_mat.set_shader_parameter("foam_tex", _noise_tex)
	if _sky and _sky.has_method("set_noise_texture"):
		_sky.set_noise_texture(_noise_tex)
	_mat.set_shader_parameter("displacements", _disp_tex)
	_mat.set_shader_parameter("normals", _norm_tex)
	_surface.material_override = _mat
	# The water samples DEPTH_TEXTURE, which Godot renders in the transparent stage; sorted by its
	# camera-centred origin it would draw last and paint over rain, portals and spray. Draw it first
	# among transparents; depth_draw_always in the shader then writes depth for everything after it.
	_mat.render_priority = -100
	add_child(_surface)
	_from = weather.duplicate()
	_target = weather.duplicate()
	set_quality(Quality.current)
	_apply_static_uniforms()


func _exit_tree() -> void:
	_disp_tex.texture_rd_rid = RID()
	_norm_tex.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_sim.free_all)


# ------------------------------------------------------------------ API
func set_weather(w: Dictionary, immediate := false) -> void:
	_from = weather.duplicate()
	for k in w.keys():
		_target[k] = w[k]
	for k in DEFAULT_WEATHER.keys():
		if not _target.has(k):
			_target[k] = DEFAULT_WEATHER[k]
	if immediate:
		_blend_t = 1.0
		weather = _target.duplicate()
		_spectrum_dirty = true
		_derive_spectrum()
		if _sky:
			_sky.apply_weather(weather, significant_wave_height, true)
		weather_changed.emit()
	else:
		_blend_t = 0.0


func set_focus(x: float, z: float) -> void:
	_focus = Vector2(x, z)
	_focus_set = true


func set_quality(preset: String) -> void:
	_preset = Quality.get_preset(preset)
	quality = preset
	Quality.current = preset
	_cascade_count = int(_preset.cascades)
	_tiles = TILE_LENGTHS_3 if _cascade_count >= 3 else TILE_LENGTHS_2
	_rebuild_mesh(String(_preset.clipmap))
	_disp_tex.texture_rd_rid = RID()
	_norm_tex.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_init_sim.bind(int(_preset.fft), _cascade_count))
	_spectrum_dirty = true
	_cur = {"valid": false}
	_prev = {"valid": false}
	_derive_spectrum()
	_apply_static_uniforms()
	if _sky and _sky.has_method("apply_quality"):
		_sky.apply_quality(_preset)


## Height and slope of the rendered surface at world (x, z): Vector3(height, dh/dx, dh/dz). O(1) bilinear
## read of the latest probe grid (fine grid near the focus, coarse grid within probe_span/2); 0 outside.
func sample(x: float, z: float) -> Vector3:
	last_dhdt = 0.0
	if not _cur.valid:
		_fallbacks += 1
		return Vector3.ZERO
	if _read(_cur, 1, x, z):
		var out := _tmp
		var half := FINE_SPAN * 0.5
		var c: Vector2 = _cur.origins[1] + Vector2(half, half)
		var edge := maxf(absf(x - c.x), absf(z - c.y)) / half
		var dhdt := _dhdt(1, x, z, out.x)
		if edge > 0.8 and _read(_cur, 0, x, z):
			var coarse := _tmp
			var t := (edge - 0.8) / 0.2
			var dhdt_c := _dhdt(0, x, z, coarse.x)
			out = out.lerp(coarse, t)
			dhdt = lerpf(dhdt, dhdt_c, t)
		last_dhdt = dhdt
		return out
	if _read(_cur, 0, x, z):
		var out := _tmp
		last_dhdt = _dhdt(0, x, z, out.x)
		return out
	_fallbacks += 1
	return Vector3.ZERO


func height_at(x: float, z: float) -> float:
	return sample(x, z).x


## Vertical velocity of the surface (m/s) from the two most recent probe grids.
func surface_velocity_y(x: float, z: float) -> float:
	sample(x, z)
	return last_dhdt


## Surface normal at (x, z).
func normal_at(x: float, z: float) -> Vector3:
	var s := sample(x, z)
	return Vector3(-s.y, 1.0, -s.z).normalized()


## Launches an analytic rogue wave (sech^2 soliton with a steepened front) that travels along
## `direction` and passes through the current focus. `height` in metres (the tempest uses ~14).
func spawn_rogue(direction: Vector2, height: float, distance := 420.0, wavelength := 320.0) -> void:
	var dir := direction.normalized() if direction.length() > 1e-3 else Vector2(0, 1)
	var speed := sqrt(G * wavelength / TAU)
	var origin := _focus - dir * distance
	var r := {"origin": origin, "dir": dir, "amp": height, "width": wavelength * 0.125, "lateral": 200.0,
		"t0": _time, "speed": speed, "travel_max": distance + 700.0}
	if _rogues.size() >= 2:
		_rogues.pop_front()
	_rogues.append(r)


## Test helper: synchronous GPU readback of the normal/displacement maps (stalls; tests only). Returns per-cascade
## foam/bubble means and the fraction of texels currently folding (J < whitecap).
func debug_map_stats() -> Dictionary:
	if not _sim_ok:
		return {}
	var out := {}
	var whitecap := _whitecap_threshold()
	var stride := 5
	for i in _cascade_count:
		var nb := _sim.rd.texture_get_data(_sim.normal_tex, i)
		var db := _sim.rd.texture_get_data(_sim.displacement_tex, i)
		var n := int(_preset.fft) * int(_preset.fft)
		var foam_sum := 0.0
		var foam_max := 0.0
		var bub_sum := 0.0
		var fold_n := 0
		var jmin := 9.0
		var count := 0
		var t := 0
		while t < n:
			var o := t * 8
			var foam := nb.decode_half(o + 4)
			var bub := nb.decode_half(o + 6)
			var j := db.decode_half(o + 6) + 1.0
			foam_sum += foam
			foam_max = maxf(foam_max, foam)
			bub_sum += bub
			jmin = minf(jmin, j)
			if j < whitecap:
				fold_n += 1
			count += 1
			t += stride
		out["c%d" % i] = {"foam_mean": snappedf(foam_sum / count, 0.001), "foam_max": snappedf(foam_max, 0.01),
			"bubbles_mean": snappedf(bub_sum / count, 0.001), "fold_frac": snappedf(float(fold_n) / count, 0.001), "j_min": snappedf(jmin, 0.01)}
	out["whitecap"] = snappedf(whitecap, 0.01)
	return out


func get_harness_state() -> Dictionary:
	return {
		"ocean_hs": snappedf(significant_wave_height, 0.01),
		"ocean_hs_measured": snappedf(measured_wave_height, 0.01),
		"readbacks": _readbacks, "fallbacks": _fallbacks, "dropped": _dropped,
		"sim": _sim_ok, "fft": int(_preset.fft), "quality": quality,
		"blend": snappedf(_blend_t, 0.01),
	}


# ------------------------------------------------------------ per frame
func _process(dt: float) -> void:
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	if cam:
		_camera_pos = cam.global_position
		_camera_xz = Vector2(_camera_pos.x, _camera_pos.z)
	if not _focus_set:
		_focus = _camera_xz
	_time += dt * time_scale
	_collect_readbacks()
	_blend_weather(dt)
	_update_rogues()
	if _sim_ok and not debug_flags.get("skip_sim", false):
		_dispatch(dt * time_scale)
	_surface.global_position = Vector3(snappedf(_camera_xz.x, _snap), 0.0, snappedf(_camera_xz.y, _snap))
	_apply_frame_uniforms()
	if _sky:
		_sky.apply_weather(weather, significant_wave_height, false)


func _blend_weather(dt: float) -> void:
	if _blend_t >= 1.0:
		return
	_blend_t = minf(1.0, _blend_t + dt / BLEND_SECONDS)
	var t := smoothstep(0.0, 1.0, _blend_t)
	for k in _target.keys():
		var a = _from.get(k, _target[k])
		var b = _target[k]
		if k == "wind_dir_deg" or k == "sun_azimuth_deg" or k == "swell_dir_deg":
			weather[k] = rad_to_deg(lerp_angle(deg_to_rad(float(a)), deg_to_rad(float(b)), t))
		elif typeof(b) == TYPE_COLOR:
			weather[k] = (a as Color).lerp(b, t) if typeof(a) == TYPE_COLOR else b
		elif typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT:
			weather[k] = lerpf(float(a), float(b), t)
		else:
			weather[k] = b
	_spectrum_dirty = true
	_derive_spectrum()
	if _blend_t >= 1.0:
		weather_changed.emit()


func _dispatch(dt: float) -> void:
	var regen := _spectrum_dirty
	_spectrum_dirty = false
	var whitecap: float = _whitecap_threshold()
	var chop: float = clampf(float(weather.choppiness), 0.0, 1.6)
	var params := PackedByteArray()
	params.resize(OceanWaveSim.CASCADE_PARAMS_BYTES)
	for i in _cascade_count:
		var tile: float = _tiles[i]
		if regen:
			var pc := OceanWaveSim.pack_push([
				1234 + 977 * i, 4321 - 613 * i, tile, tile,
				_spec.alpha, _spec.wp, _spec.u, _spec.wind_angle, DEPTH,
				_spec.swell_amp, _spec.ws, _spec.sigma, _spec.swell_angle,
				_spec.spread, 1.0, _k_lo(i), _k_hi[i], i])
			RenderingServer.call_on_render_thread(_sim.generate_spectrum.bind(pc))
		var disp_scale := _map_scales[i].z
		# low/medium: the two long cascades alternate frames (their waves move a fraction of a texel per frame)
		var skip := bool(_preset.get("cascade_skip", false)) and i < 2 and (_frame + i) % 2 == 0 and not regen
		var cdt := minf(_time - _cascade_last_time[i], 0.1)
		if not skip:
			_cascade_last_time[i] = _time
		_encode_vec4(params, i * 16, Vector4(tile, tile, DEPTH, _time + 120.0 + PI * i))
		_encode_vec4(params, 48 + i * 16, Vector4(whitecap, 2.7, 0.7, 0.35))
		_encode_vec4(params, 96 + i * 16, Vector4(0.05, cdt, disp_scale * chop, 1.0 if skip else 0.0))
	RenderingServer.call_on_render_thread(_sim.step_all.bind(params))
	if not debug_flags.get("skip_probe", false):
		_dispatch_probe()


func _dispatch_probe() -> void:
	if _inflight > 3:
		_dropped += 1
		return
	_grids[0].span = probe_span
	var params := PackedByteArray()
	params.resize(160)
	for i in 4:
		var v := _map_scales[i] if i < _map_scales.size() else Vector4.ZERO
		params.encode_float(i * 16, v.x)
		params.encode_float(i * 16 + 4, v.y)
		params.encode_float(i * 16 + 8, v.z)
		params.encode_float(i * 16 + 12, v.w)
	_encode_vec4(params, 64, _disp_fade)
	var rv := _rogue_vectors()
	_encode_vec4(params, 80, rv[0])
	_encode_vec4(params, 96, rv[1])
	_encode_vec4(params, 112, rv[2])
	_encode_vec4(params, 128, rv[3])
	_encode_vec4(params, 144, Vector4(clampf(float(weather.choppiness), 0.0, 1.6), float(_cascade_count), 0.0, 0.0))
	var pcs := []
	var counts := []
	var origins := []
	for g in _grids:
		var span: float = g.span
		var cells: int = g.cells
		var origin := _focus - Vector2(span, span) * 0.5
		var cell := span / float(cells - 1)
		var eps := clampf(cell * 0.25, 0.15, 0.75)
		pcs.append(OceanWaveSim.pack_push([origin.x, origin.y, _camera_xz.x, _camera_xz.y, span, cells, int(g.offset), eps]))
		counts.append(cells * cells)
		origins.append(origin)
	var ctx := {"origins": origins, "time": _time, "frame": _frame}
	_inflight += 1
	RenderingServer.call_on_render_thread(_sim.probe.bind(params, pcs, counts, _on_probe_data.bind(ctx)))


func _on_probe_data(data: PackedByteArray, ctx: Dictionary) -> void:
	_arrived_mutex.lock()
	_arrived.append({"data": data, "ctx": ctx})
	_arrived_mutex.unlock()


func _collect_readbacks() -> void:
	_arrived_mutex.lock()
	var items := _arrived
	_arrived = []
	_arrived_mutex.unlock()
	if items.is_empty():
		return
	_inflight = maxi(0, _inflight - items.size())
	var last: Dictionary = items[items.size() - 1]
	var floats: PackedFloat32Array = (last.data as PackedByteArray).to_float32_array()
	if floats.size() < (COARSE_CELLS * COARSE_CELLS + FINE_CELLS * FINE_CELLS) * 4:
		return
	_prev = _cur
	_cur = {"valid": true, "data": floats, "origins": last.ctx.origins, "time": last.ctx.time, "frame": last.ctx.frame,
		"spans": [probe_span, FINE_SPAN]}
	_readbacks += 1
	if _readbacks % 4 == 0:
		_measure_hs(floats)


func _measure_hs(d: PackedFloat32Array) -> void:
	var n := COARSE_CELLS * COARSE_CELLS
	var sum := 0.0
	var sq := 0.0
	var count := 0
	var i := 0
	while i < n:
		var h := d[i * 4]
		if is_finite(h):
			sum += h
			sq += h * h
			count += 1
		i += 3
	if count < 8:
		return
	var mean := sum / count
	var var_h := maxf(sq / count - mean * mean, 0.0)
	var hs := 4.0 * sqrt(var_h)
	measured_wave_height = hs if measured_wave_height == 0.0 else lerpf(measured_wave_height, hs, 0.1)


## Bilinear read of one grid into _tmp; false when (x, z) is outside it.
func _read(state: Dictionary, gi: int, x: float, z: float) -> bool:
	if not state.valid:
		return false
	var g: Dictionary = _grids[gi]
	var n: int = g.cells
	var span: float = state.spans[gi]
	var origin: Vector2 = state.origins[gi]
	var s := float(n - 1) / span
	var fx := (x - origin.x) * s
	var fz := (z - origin.y) * s
	if fx < 0.0 or fz < 0.0 or fx > float(n - 1) or fz > float(n - 1):
		return false
	var ix := mini(int(fx), n - 2)
	var iz := mini(int(fz), n - 2)
	var tx := fx - ix
	var tz := fz - iz
	var d: PackedFloat32Array = state.data
	var base: int = int(g.offset)
	var i00 := (base + iz * n + ix) * 4
	var i10 := i00 + 4
	var i01 := i00 + n * 4
	var i11 := i01 + 4
	var w00 := (1.0 - tx) * (1.0 - tz)
	var w10 := tx * (1.0 - tz)
	var w01 := (1.0 - tx) * tz
	var w11 := tx * tz
	var h := d[i00] * w00 + d[i10] * w10 + d[i01] * w01 + d[i11] * w11
	if not is_finite(h):
		return false
	_tmp = Vector3(h,
		d[i00 + 1] * w00 + d[i10 + 1] * w10 + d[i01 + 1] * w01 + d[i11 + 1] * w11,
		d[i00 + 2] * w00 + d[i10 + 2] * w10 + d[i01 + 2] * w01 + d[i11 + 2] * w11)
	return true


func _dhdt(gi: int, x: float, z: float, h_now: float) -> float:
	if not _prev.valid:
		return 0.0
	var dt: float = _cur.time - _prev.time
	if dt < 1e-4 or dt > 0.25:
		return 0.0
	if _read(_prev, gi, x, z):
		return clampf((h_now - _tmp.x) / dt, -12.0, 12.0)
	return 0.0


# ------------------------------------------------------- spectrum params
func _derive_spectrum() -> void:
	var u := maxf(float(weather.wind_speed), 0.3)
	var fetch := FETCH_KM * 1000.0
	var wp_fetch := 22.0 * pow(G * G / (u * fetch), 1.0 / 3.0)
	var wp_pm := 0.855 * G / u
	var developed := wp_pm > wp_fetch
	var wp := maxf(wp_fetch, wp_pm)
	var alpha := 0.0081 if developed else 0.076 * pow(u * u / (fetch * G), 0.22)
	var hs_s := maxf(float(weather.swell_hs), 0.0)
	var period := maxf(float(weather.swell_period), 3.0)
	var ws := TAU / period
	var sigma := 0.13 * ws
	var m0_s := pow(hs_s / 4.0, 2.0)
	var swell_amp := m0_s / (sigma * sqrt(TAU))
	var wind_dir := deg_to_rad(float(weather.wind_dir_deg))
	var swell_dir := deg_to_rad(float(weather.get("swell_dir_deg", float(weather.wind_dir_deg) - 25.0)))
	# world travel direction W = (sin a, cos a) in xz; the simulation's +wt sign makes waves travel toward -k
	var wind_angle := atan2(cos(wind_dir), sin(wind_dir)) + PI
	var swell_angle := atan2(cos(swell_dir), sin(swell_dir)) + PI
	_spec = {"u": u, "wp": wp, "alpha": alpha, "ws": ws, "sigma": sigma, "swell_amp": swell_amp,
		"wind_angle": wind_angle, "swell_angle": swell_angle, "spread": float(weather.get("spread", 0.22))}
	# cascade tiling and band limits
	var n := _cascade_count
	var fft := int(_preset.fft)
	_map_scales.resize(4)
	_k_hi.resize(n)
	var fades: Array = DISP_FADE_3 if n >= 3 else DISP_FADE_2
	var nf := [0.0, 0.0, 0.0, 0.0]
	var df := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		_map_scales[i] = Vector4.ZERO
	for i in n:
		var tile: float = _tiles[i]
		var texel := tile / float(fft)
		var k_nyq := TAU / (2.5 * texel)
		if i < n - 1:
			_k_hi[i] = minf(TAU / (_tiles[i + 1] / 4.0), k_nyq)
		else:
			_k_hi[i] = k_nyq
		var dscale := 1.0 if i < 2 else 0.85
		_map_scales[i] = Vector4(1.0 / tile, 1.0 / tile, dscale, 0.0)
		df[i] = fades[i]
		nf[i] = texel * 350.0
	_disp_fade = Vector4(df[0], df[1], df[2], df[3])
	_normal_fade = Vector4(nf[0], nf[1], nf[2], nf[3])
	significant_wave_height = _integrate_hs(_k_hi[n - 1])


## Per-cascade Jacobian below which a texel counts as breaking (each cascade carries only its band, so this sits
## well above 0); the weather's `foam` (0.35 calm .. 1.5 squall) opens it up a little.
func _whitecap_threshold() -> float:
	return 0.60 + 0.12 * clampf(float(weather.foam) / 1.5, 0.0, 1.0)


func _k_lo(i: int) -> float:
	return 1e-4 if i == 0 else _k_hi[i - 1]


func _integrate_hs(k_max: float) -> float:
	var m0 := 0.0
	var w := 0.05
	var ratio := 1.03
	while w < 25.0:
		var dw := w * (ratio - 1.0)
		var k := w * w / G
		if k < k_max:
			var s := 0.0
			if _spec.alpha > 0.0:
				var wp: float = _spec.wp
				var sg := 0.07 if w <= wp else 0.09
				var r := exp(-(w - wp) * (w - wp) / (2.0 * sg * sg * wp * wp))
				s += _spec.alpha * G * G / pow(w, 5.0) * exp(-1.25 * pow(wp / w, 4.0)) * pow(3.3, r)
			var dws: float = w - _spec.ws
			s += _spec.swell_amp * exp(-dws * dws / (2.0 * _spec.sigma * _spec.sigma))
			m0 += s * dw
		w *= ratio
	return 4.0 * sqrt(m0)


# ---------------------------------------------------------------- rogue
func _update_rogues() -> void:
	var keep := []
	for r in _rogues:
		var travel: float = (_time - r.t0) * r.speed
		if travel < r.travel_max:
			keep.append(r)
	_rogues = keep


func _rogue_vectors() -> Array:
	var out := [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	for i in mini(_rogues.size(), 2):
		var r: Dictionary = _rogues[i]
		var age: float = _time - r.t0
		var travel: float = age * r.speed
		var env: float = smoothstep(0.0, 4.0, age) * (1.0 - smoothstep(r.travel_max - 250.0, r.travel_max, travel))
		out[i * 2] = Vector4(r.origin.x, r.origin.y, r.dir.x, r.dir.y)
		out[i * 2 + 1] = Vector4(r.amp * env, r.width, r.lateral, travel)
	return out


# -------------------------------------------------------------- uniforms
func _apply_static_uniforms() -> void:
	_mat.set_shader_parameter("num_cascades", _cascade_count)
	_mat.set_shader_parameter("map_scales", _map_scales)
	_mat.set_shader_parameter("disp_fade", _disp_fade)
	_mat.set_shader_parameter("normal_fade", _normal_fade)
	_mat.set_shader_parameter("use_bicubic", bool(_preset.bicubic))
	_mat.set_shader_parameter("debug_view", debug_view)


func _apply_frame_uniforms() -> void:
	var rv := _rogue_vectors()
	_mat.set_shader_parameter("time", _time)
	_mat.set_shader_parameter("rogue0", rv[0])
	_mat.set_shader_parameter("rogue0b", rv[1])
	_mat.set_shader_parameter("rogue1", rv[2])
	_mat.set_shader_parameter("rogue1b", rv[3])
	if _blend_t < 1.0 or _frame < 3:
		var wc: Color = weather.water_color
		var wd: Color = weather.get("water_deep", wc * 0.45)
		var lin := wc.srgb_to_linear()
		var lind := wd.srgb_to_linear()
		_mat.set_shader_parameter("water_scatter", Vector3(lin.r, lin.g, lin.b))
		_mat.set_shader_parameter("water_deep", Vector3(lind.r, lind.g, lind.b))
		_mat.set_shader_parameter("chop", clampf(float(weather.choppiness), 0.0, 1.6))
		var a := deg_to_rad(float(weather.wind_dir_deg))
		_mat.set_shader_parameter("wind_dir", Vector2(sin(a), cos(a)))
		var u := float(weather.wind_speed)
		_mat.set_shader_parameter("whitecap_cov", 3.84e-6 * pow(maxf(u, 0.0), 3.41))
		_mat.set_shader_parameter("foam_strength", clampf(float(weather.foam), 0.0, 2.0))
		_mat.set_shader_parameter("whitecap", _whitecap_threshold())
		_mat.set_shader_parameter("hs", maxf(significant_wave_height, 0.3))
		_mat.set_shader_parameter("map_scales", _map_scales)
		_mat.set_shader_parameter("disp_fade", _disp_fade)
		_mat.set_shader_parameter("normal_fade", _normal_fade)


# ------------------------------------------------------------- GPU init
func _init_sim(fft: int, cascades: int) -> void:
	_sim.init(fft, cascades, COARSE_CELLS * COARSE_CELLS + FINE_CELLS * FINE_CELLS)
	_sim_ok = _sim.is_ready
	if _sim_ok:
		_disp_tex.texture_rd_rid = _sim.displacement_tex
		_norm_tex.texture_rd_rid = _sim.normal_tex
		# the RS texture behind a TextureLayeredRD is recreated when its RID changes; rebind so the material sees it
		_mat.set_shader_parameter("displacements", _disp_tex)
		_mat.set_shader_parameter("normals", _norm_tex)
	else:
		push_error("Ocean: wave simulation unavailable: " + _sim.last_error)


# ---------------------------------------------------------------- mesh
func _rebuild_mesh(clipmap: String) -> void:
	var cfg: Dictionary = Quality.CLIPMAPS.get(clipmap, Quality.CLIPMAPS["medium"])
	var cell: float = cfg.cell
	var block: int = cfg.block
	var rings: int = cfg.rings
	_surface.mesh = _build_clipmap(cell, block, rings)
	var outer := float(block / 2) * cell * float(1 << rings)
	_surface.custom_aabb = AABB(Vector3(-outer, -120.0, -outer), Vector3(outer * 2.0, 240.0, outer * 2.0))
	_snap = cell * 2.0


## Concentric-ring geometry clipmap: a block x block centre at `cell` metres, then `rings` square
## annuli that each double the cell size. Ring inner edges are stitched to the finer level with
## triangle fans, so the mesh is watertight (no T-junction cracks) out to the horizon.
static func _build_clipmap(c0: float, n: int, rings: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()      # x = cell size (m) of the level that created the vertex
	var idx := PackedInt32Array()
	var lookup := {}
	var half := n / 2
	var cur_cell := [c0]
	var vid := func(ix: int, iz: int) -> int:
		var key := Vector2i(ix, iz)
		if lookup.has(key):
			return lookup[key]
		var i := verts.size()
		verts.append(Vector3(float(ix) * c0, 0.0, float(iz) * c0))
		uvs.append(Vector2(cur_cell[0], 0.0))
		lookup[key] = i
		return i
	var tri := func(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)
	var quad := func(x0: int, z0: int, x1: int, z1: int) -> void:
		var a: int = vid.call(x0, z0)
		var b: int = vid.call(x1, z0)
		var c: int = vid.call(x1, z1)
		var d: int = vid.call(x0, z1)
		tri.call(a, b, c)
		tri.call(a, c, d)
	# centre block
	for iz in range(-half, half):
		for ix in range(-half, half):
			quad.call(ix, iz, ix + 1, iz + 1)
	# rings
	var q := n / 4
	for level in range(1, rings + 1):
		var s := 1 << level
		cur_cell[0] = c0 * float(s)
		for iz in range(-half, half):
			for ix in range(-half, half):
				if ix >= -q and ix < q and iz >= -q and iz < q:
					continue
				var x0 := ix * s
				var z0 := iz * s
				var x1 := x0 + s
				var z1 := z0 + s
				var xm := x0 + s / 2
				var zm := z0 + s / 2
				var in_z := iz >= -q and iz < q
				var in_x := ix >= -q and ix < q
				if ix == q and in_z:
					# left edge (x0) touches the finer block: split it
					var a: int = vid.call(x0, z0)
					var m: int = vid.call(x0, zm)
					var d: int = vid.call(x0, z1)
					var b: int = vid.call(x1, z0)
					var c: int = vid.call(x1, z1)
					tri.call(a, b, m)
					tri.call(m, b, c)
					tri.call(m, c, d)
				elif ix == -q - 1 and in_z:
					var a: int = vid.call(x0, z0)
					var b: int = vid.call(x1, z0)
					var m: int = vid.call(x1, zm)
					var c: int = vid.call(x1, z1)
					var d: int = vid.call(x0, z1)
					tri.call(a, b, m)
					tri.call(a, m, d)
					tri.call(d, m, c)
				elif iz == q and in_x:
					var a: int = vid.call(x0, z0)
					var m: int = vid.call(xm, z0)
					var b: int = vid.call(x1, z0)
					var c: int = vid.call(x1, z1)
					var d: int = vid.call(x0, z1)
					tri.call(a, m, d)
					tri.call(m, c, d)
					tri.call(m, b, c)
				elif iz == -q - 1 and in_x:
					var a: int = vid.call(x0, z0)
					var b: int = vid.call(x1, z0)
					var c: int = vid.call(x1, z1)
					var m: int = vid.call(xm, z1)
					var d: int = vid.call(x0, z1)
					tri.call(a, b, m)
					tri.call(b, c, m)
					tri.call(a, m, d)
				else:
					quad.call(x0, z0, x1, z1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Seamless RGBA noise for the foam froth: r = raft cells, g = fine detail, b/a = streak noise.
static func _make_noise_texture() -> ImageTexture:
	var size := 256
	var cfg := [
		[FastNoiseLite.TYPE_CELLULAR, 0.045, 11],
		[FastNoiseLite.TYPE_PERLIN, 0.07, 12],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.028, 13],
		[FastNoiseLite.TYPE_SIMPLEX, 0.09, 14],
	]
	var chans: Array[PackedByteArray] = []
	for c in cfg:
		var fn := FastNoiseLite.new()
		fn.noise_type = c[0]
		fn.frequency = c[1]
		fn.seed = c[2]
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 3
		if c[0] == FastNoiseLite.TYPE_CELLULAR:
			fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			fn.fractal_octaves = 1
		var img := fn.get_seamless_image(size, size)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var out := PackedByteArray()
	out.resize(size * size * 4)
	for i in size * size:
		var j := i * 4
		out[j] = chans[0][i]
		out[j + 1] = chans[1][i]
		out[j + 2] = chans[2][i]
		out[j + 3] = chans[3][i]
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _encode_vec4(buf: PackedByteArray, offset: int, v: Vector4) -> void:
	buf.encode_float(offset, v.x)
	buf.encode_float(offset + 4, v.y)
	buf.encode_float(offset + 8, v.z)
	buf.encode_float(offset + 12, v.w)
