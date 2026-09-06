class_name OceanWaveSim
extends RefCounted
## RenderingDevice compute pipeline for the FFT ocean (port of GodotOceanWaves, MIT, Ethan Truong):
## spectrum -> time modulation -> row FFT -> transpose -> row FFT -> unpack (displacement + normal/foam maps),
## plus the CPU sampling probe that evaluates the displaced surface on small grids and reads it back.
##
## Godot 4.7 notes baked in here:
##   * every uniform set is created against the exact shader it is bound to (4.7 validates image/buffer
##     access qualifiers per shader, so sets cannot be shared between e.g. a `writeonly` and a `readonly` user),
##   * push constants are packed to their exact std430 size (no 16-byte padding),
##   * one compute list per dispatch so the render graph inserts the barriers/layout transitions.
## All methods run on the rendering thread (Ocean.gd routes them through RenderingServer.call_on_render_thread;
## with the default single-threaded model that is simply the main thread).

const SHADER_DIR := "res://shaders/"
const NUM_SPECTRA := 4
const MAX_CASCADES := 3
const PROBE_PARAMS_BYTES := 160  # std140: vec4 map_scales[4], disp_fade, rogue0, rogue0b, rogue1, rogue1b, misc
const CASCADE_PARAMS_BYTES := 144  # std140: vec4 tile_depth_time[3], foam_a[3], foam_b[3]

var rd: RenderingDevice
var map_size := 256
var num_cascades := 3
var is_ready := false
var last_error := ""

var _shaders := {}
var _pipelines := {}
var _sets := {}
var _rids: Array[RID] = []

var spectrum_tex: RID
var displacement_tex: RID
var normal_tex: RID
var butterfly_buf: RID
var fft_buf: RID
var probe_buf: RID
var probe_params_buf: RID
var cascade_params_buf: RID
var sampler: RID
var probe_capacity := 0



func init(p_map_size: int, p_num_cascades: int, probe_nodes: int) -> void:
	free_all()
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		last_error = "no RenderingDevice (headless or compatibility renderer)"
		push_error("OceanWaveSim: " + last_error)
		return
	map_size = p_map_size
	num_cascades = clampi(p_num_cascades, 1, MAX_CASCADES)
	probe_capacity = probe_nodes

	var defines := "#define MAP_SIZE %d\n" % map_size
	for name in ["spectrum", "modulate", "butterfly", "fft", "transpose", "unpack", "probe"]:
		var sh := _load_shader(name, defines)
		if not sh.is_valid():
			return
		_shaders[name] = sh

	var n := map_size
	var stages := int(round(log(n) / log(2)))
	spectrum_tex = _create_texture(n, num_cascades, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT, 16)
	var map_usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	displacement_tex = _create_texture(n, num_cascades, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, map_usage, 8)
	normal_tex = _create_texture(n, num_cascades, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, map_usage, 8)
	butterfly_buf = _push(rd.storage_buffer_create(stages * n * 16))
	fft_buf = _push(rd.storage_buffer_create(num_cascades * n * n * NUM_SPECTRA * 2 * 8))
	probe_buf = _push(rd.storage_buffer_create(maxi(probe_capacity, 64) * 16))
	var params_zero := PackedByteArray()
	params_zero.resize(PROBE_PARAMS_BYTES)
	probe_params_buf = _push(rd.uniform_buffer_create(PROBE_PARAMS_BYTES, params_zero))
	var cparams_zero := PackedByteArray()
	cparams_zero.resize(CASCADE_PARAMS_BYTES)
	cascade_params_buf = _push(rd.uniform_buffer_create(CASCADE_PARAMS_BYTES, cparams_zero))

	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler = _push(rd.sampler_create(ss))

	# Uniform sets: one per shader, matching each shader's declared access.
	_sets["spectrum"] = _make_set(_shaders["spectrum"], [
		_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [spectrum_tex])])
	_sets["modulate"] = _make_set(_shaders["modulate"], [
		_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [spectrum_tex]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, [fft_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [cascade_params_buf])])
	_sets["butterfly"] = _make_set(_shaders["butterfly"], [
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [butterfly_buf])])
	_sets["fft"] = _make_set(_shaders["fft"], [
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [butterfly_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, [fft_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [cascade_params_buf])])
	_sets["transpose"] = _make_set(_shaders["transpose"], [
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, [butterfly_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, [fft_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [cascade_params_buf])])
	_sets["unpack"] = _make_set(_shaders["unpack"], [
		_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [displacement_tex]),
		_u(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [normal_tex]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [fft_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 3, [cascade_params_buf])])
	_sets["probe"] = _make_set(_shaders["probe"], [
		_u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [sampler, displacement_tex]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1, [probe_buf]),
		_u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 2, [probe_params_buf])])

	for name in _shaders.keys():
		_pipelines[name] = _push(rd.compute_pipeline_create(_shaders[name]))

	# Butterfly factors once per map size.
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["butterfly"])
	rd.compute_list_bind_uniform_set(cl, _sets["butterfly"], 0)
	rd.compute_list_dispatch(cl, maxi(n / 2 / 64, 1), stages, 1)
	rd.compute_list_end()
	is_ready = true


## Regenerates the initial spectrum of one cascade. `pc` is the 72-byte push constant (see the shader).
func generate_spectrum(pc: PackedByteArray) -> void:
	if not is_ready:
		return
	var g := map_size / 16
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["spectrum"])
	rd.compute_list_bind_uniform_set(cl, _sets["spectrum"], 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, g, g, 1)
	rd.compute_list_end()


## Advances all cascades one step: modulate -> row FFT -> transpose -> row FFT -> unpack, five dispatches
## in total (cascades ride on the dispatch z axis; per-cascade parameters come from `params`, the
## 144-byte std140 CascadeParams block: tile_depth_time[3], foam_a[3], foam_b[3]).
func step_all(params: PackedByteArray) -> void:
	if not is_ready:
		return
	var n := map_size
	var g := n / 16
	var c := num_cascades
	rd.buffer_update(cascade_params_buf, 0, params.size(), params)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["modulate"])
	rd.compute_list_bind_uniform_set(cl, _sets["modulate"], 0)
	rd.compute_list_dispatch(cl, g, g, c)
	rd.compute_list_end()

	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["fft"])
	rd.compute_list_bind_uniform_set(cl, _sets["fft"], 0)
	rd.compute_list_dispatch(cl, 1, n, NUM_SPECTRA * c)
	rd.compute_list_end()

	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["transpose"])
	rd.compute_list_bind_uniform_set(cl, _sets["transpose"], 0)
	rd.compute_list_dispatch(cl, n / 32, n / 32, NUM_SPECTRA * c)
	rd.compute_list_end()

	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["fft"])
	rd.compute_list_bind_uniform_set(cl, _sets["fft"], 0)
	rd.compute_list_dispatch(cl, 1, n, NUM_SPECTRA * c)
	rd.compute_list_end()

	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["unpack"])
	rd.compute_list_bind_uniform_set(cl, _sets["unpack"], 0)
	rd.compute_list_dispatch(cl, g, g, c)
	rd.compute_list_end()


## Evaluates the surface on the probe grids. `params` is the 112-byte std140 block, `grids` a list of
## 32-byte push constants (one per grid). Then schedules an async readback delivered to `callback(data)`.
func probe(params: PackedByteArray, grids: Array, node_counts: Array, callback: Callable) -> void:
	if not is_ready:
		return
	rd.buffer_update(probe_params_buf, 0, params.size(), params)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipelines["probe"])
	rd.compute_list_bind_uniform_set(cl, _sets["probe"], 0)
	for i in grids.size():
		var pc: PackedByteArray = grids[i]
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, ceili(float(node_counts[i]) / 64.0), 1, 1)
	rd.compute_list_end()
	var total := 0
	for c in node_counts:
		total += int(c)
	rd.buffer_get_data_async(probe_buf, callback, 0, total * 16)


## Debug helper: synchronous copy of one displacement layer (stalls the GPU; tests only).
func read_displacement_layer(layer: int) -> PackedByteArray:
	if not is_ready:
		return PackedByteArray()
	return rd.texture_get_data(displacement_tex, layer)


func free_all() -> void:
	is_ready = false
	if rd == null:
		return
	for k in _sets.keys():
		if _sets[k].is_valid():
			rd.free_rid(_sets[k])
	_sets.clear()
	for i in range(_rids.size() - 1, -1, -1):
		if _rids[i].is_valid():
			rd.free_rid(_rids[i])
	_rids.clear()
	_pipelines.clear()
	_shaders.clear()
	spectrum_tex = RID()
	displacement_tex = RID()
	normal_tex = RID()


# ---------------------------------------------------------------- helpers
static func pack_push(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(values.size() * 4)
	for i in values.size():
		var v = values[i]
		match typeof(v):
			TYPE_INT, TYPE_BOOL:
				out.encode_s32(i * 4, int(v))
			_:
				out.encode_float(i * 4, float(v))
	return out


func _push(rid: RID) -> RID:
	if rid.is_valid():
		_rids.append(rid)
	return rid


func _u(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _make_set(shader: RID, uniforms: Array) -> RID:
	var typed: Array[RDUniform] = []
	for u in uniforms:
		typed.append(u)
	return rd.uniform_set_create(typed, shader, 0)


func _create_texture(size: int, layers: int, format: RenderingDevice.DataFormat, usage: int, bytes_per_texel: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = size
	fmt.height = size
	fmt.depth = 1
	fmt.array_layers = layers
	fmt.mipmaps = 1
	fmt.format = format
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt.usage_bits = usage
	var data: Array[PackedByteArray] = []
	for i in layers:
		var layer := PackedByteArray()
		layer.resize(size * size * bytes_per_texel)
		data.append(layer)
	return _push(rd.texture_create(fmt, RDTextureView.new(), data))


func _load_shader(name: String, defines: String) -> RID:
	var path := SHADER_DIR + "ocean_compute_%s.glsl" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "cannot open " + path
		push_error("OceanWaveSim: " + last_error)
		return RID()
	var text := f.get_as_text()
	# Strip the importer header and inject compile-time defines after #version.
	var lines := text.split("\n")
	var out := PackedStringArray()
	for line in lines:
		if line.begins_with("#[compute]"):
			continue
		out.append(line)
		if line.begins_with("#version"):
			out.append(defines)
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = "\n".join(out)
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		last_error = "%s: %s" % [name, spirv.compile_error_compute]
		push_error("OceanWaveSim shader compile error in " + last_error)
		return RID()
	return _push(rd.shader_create_from_spirv(spirv, "ocean_" + name))
