class_name StubOcean
extends Node3D
## Stand-in for the FFT Ocean (same API as ocean/Ocean.gd in docs/GODOT-PORT.md) so boats,
## worlds and races can be developed and tested before the real ocean lands.
## Three Gerstner waves evaluated identically on the CPU (sample) and in the vertex shader.

signal weather_changed

var significant_wave_height := 0.8
var _weather := {
	"wind_speed": 5.0, "wind_dir_deg": 20.0, "swell_hs": 0.8, "swell_period": 9.0, "choppiness": 1.0,
	"foam": 0.4, "water_color": Color(0.02, 0.28, 0.42), "sun_elev_deg": 40.0, "sun_azimuth_deg": 110.0,
	"cloud_cover": 0.2, "rain": 0.0, "fog": 0.0, "lightning_rate": 0.0,
}
var _t := 0.0
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
# wave params: amplitude, wavelength, direction (radians), steepness
var _waves: Array = []


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	plane.subdivide_width = 320
	plane.subdivide_depth = 320
	_mesh.mesh = plane
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ocean/stub_ocean.gdshader")
	_mesh.material_override = _mat
	_mesh.extra_cull_margin = 64.0
	add_child(_mesh)
	_rebuild_waves()


func set_weather(w: Dictionary, _immediate := false) -> void:
	for k in w.keys():
		_weather[k] = w[k]
	_rebuild_waves()
	weather_changed.emit()


func set_quality(_preset: String) -> void:
	pass


func set_focus(x: float, z: float) -> void:
	# the stub is analytic everywhere; just keep the mesh under the player
	_mesh.position = Vector3(snappedf(x, 8.0), 0.0, snappedf(z, 8.0))


func _rebuild_waves() -> void:
	var hs: float = _weather.swell_hs
	var period: float = _weather.swell_period
	var dir := deg_to_rad(_weather.wind_dir_deg)
	var g := 9.81
	var l0 := g * period * period / TAU
	significant_wave_height = hs
	_waves = [
		[hs * 0.5, l0, dir, 0.6],
		[hs * 0.25, l0 * 0.45, dir + 0.5, 0.7],
		[hs * 0.12, l0 * 0.18, dir - 0.9, 0.8],
	]
	for i in 3:
		var w: Array = _waves[i]
		_mat.set_shader_parameter("wave%d" % i, Vector4(float(w[0]), float(w[1]), float(w[2]), float(w[3])))
	_mat.set_shader_parameter("water_color", _weather.water_color)
	_mat.set_shader_parameter("foam_amount", _weather.foam)


func _process(dt: float) -> void:
	_t += dt
	_mat.set_shader_parameter("time", _t)


func _height(x: float, z: float, t: float) -> float:
	var h := 0.0
	for w in _waves:
		var amp: float = w[0]
		var k: float = TAU / float(w[1])
		var c: float = sqrt(9.81 / k)
		var d := Vector2(cos(float(w[2])), sin(float(w[2])))
		var phase: float = k * (d.x * x + d.y * z) - c * k * t
		h += amp * cos(phase)
	return h


func sample(x: float, z: float) -> Vector3:
	var e := 0.5
	var h := _height(x, z, _t)
	return Vector3(h, (_height(x + e, z, _t) - h) / e, (_height(x, z + e, _t) - h) / e)


func height_at(x: float, z: float) -> float:
	return _height(x, z, _t)


func surface_velocity_y(x: float, z: float) -> float:
	return (_height(x, z, _t) - _height(x, z, _t - 1.0 / 60.0)) * 60.0
