class_name SubmarineVisual
extends Node3D
## Toy submarine visual — port of buildSubVisual() in the web game's src/game/Submarine.js.
## Local +Z is forward, origin at the hull centre (the physics position). Chunky flat colours
## merged into one ArrayMesh (one surface per colour), with separate nodes for the animated parts:
## prop (spins with throttle), stern planes (tilt with dive), upper rudder (swings with steer),
## the kid under the glass bubble (leans into turns), two headlight SpotLight3Ds with emissive
## discs and translucent cones that fade in under water, and a bubble trail (GPUParticles3D)
## clamped below the sea surface. Three colour variants (yellow / orange / mint).
##
## `update(dt, body)` reads body.throttle/steer/dive/speed/submersion/surface_y/position/forward
## (SubPhysics). With `auto_update` on, the node drives itself from its parent each frame.

const PALETTE := {
	"white": "f4f4f8", "cream": "ffe6c4", "red": "d84c48", "orange": "ff7a3d", "yellow": "ffc236",
	"navy": "4f52c6", "purple": "9d6cf0", "dark": "33343b", "steel": "b7bccb", "glass": "c6ecff",
	"skin": "f3b98e", "porthole": "1d3b6e", "mint": "6ee7c2",
}
const SUB_COLORS: Array = ["yellow", "orange", "mint"]
const HELMETS: Array = ["red", "navy", "purple"]
const HULL_R := 0.95
const BUBBLE_LIFE := 3.2

@export var color_index := 0
@export var auto_update := true

var triangles := 0
var built := false

var _prop: Node3D
var _planes: Node3D
var _rudder: Node3D
var _kid: Node3D
var _torso: Node3D
var _head: Node3D
var _lamps: Array[SpotLight3D] = []
var _cone_mat: StandardMaterial3D
var _bubbles: GPUParticles3D
var _bubble_mat: ShaderMaterial
var _spin := 0.0
var _dive := 0.0
var _steer := 0.0
var _throttle := 0.0
var _lean := 0.0

# per-colour surface bins: key -> SurfaceTool
var _bins: Dictionary = {}
var _bin_mats: Dictionary = {}
var _prop_shader: Shader


func _ready() -> void:
	if not built:
		build(color_index)


func _process(dt: float) -> void:
	if auto_update and built:
		var body := get_parent()
		if body != null and "is_sub" in body:
			update(dt, body)


# ------------------------------------------------------------------ helpers
static func pal(name: String) -> Color:
	return Color.html(PALETTE[name]) if PALETTE.has(name) else Color.html(name)


func _mat(color: Color, roughness := 0.5, metal := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _prop_shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness_v", roughness)
	m.set_shader_parameter("metallic_v", metal)
	m.set_shader_parameter("absorb", Vector3(0.016, 0.006, 0.0025))   # ~1/3 of the water column: the toy stays yellow at hoop depth, like the web
	return m


## Append `mesh` (a primitive) at `xform` into the bin of `color`.
func _add(mesh: Mesh, color: Color, xform: Transform3D, roughness := 0.5, metal := 0.0) -> void:
	var key := "%s|%.2f|%.2f" % [color.to_html(false), roughness, metal]
	if not _bins.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_bins[key] = st
		_bin_mats[key] = _mat(color, roughness, metal)
	(_bins[key] as SurfaceTool).append_from(mesh, 0, xform)


## Commit the bins into one ArrayMesh (one surface per colour) and clear them.
func _flush(name: String, parent: Node3D, local := Transform3D.IDENTITY) -> MeshInstance3D:
	var am := ArrayMesh.new()
	for key in _bins:
		var st: SurfaceTool = _bins[key]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, _bin_mats[key])
	_bins.clear()
	_bin_mats.clear()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = am
	mi.transform = local
	parent.add_child(mi)
	triangles += am.get_faces().size() / 3
	return mi


static func T(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


static func RX(a: float) -> Basis:
	return Basis(Vector3.RIGHT, a)


static func RY(a: float) -> Basis:
	return Basis(Vector3.UP, a)


static func RZ(a: float) -> Basis:
	return Basis(Vector3.BACK, a)


static func box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


static func cyl(r_top: float, r_bot: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func sphere(r: float, w := 10, h := 7, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.radial_segments = w
	s.rings = h
	s.is_hemisphere = hemi
	return s


static func torus(radius: float, tube: float, tube_seg := 5, around := 12) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - tube
	t.outer_radius = radius + tube
	t.rings = around
	t.ring_segments = tube_seg
	return t


# -------------------------------------------------------------------- build
func build(ci: int) -> void:
	color_index = posmod(ci, SUB_COLORS.size())
	_prop_shader = load("res://shaders/underwater_prop.gdshader")
	var color := pal(SUB_COLORS[color_index])
	var white := pal("white")
	var dark := pal("dark")
	var steel := pal("steel")
	var R := HULL_R
	triangles = 0

	# Cigar hull along +Z, two white bands, a dark keel strip.
	var capsule := CapsuleMesh.new()
	capsule.radius = R
	capsule.height = 4.1 + 2.0 * R
	capsule.radial_segments = 12
	capsule.rings = 3
	_add(capsule, color, T(0, 0, 0, RX(PI / 2)), 0.4)
	_add(cyl(R + 0.03, R + 0.03, 0.3, 12), white, T(0, 0, -1.25, RX(PI / 2)), 0.45)
	_add(cyl(R + 0.03, R + 0.03, 0.3, 12), white, T(0, 0, 0.9, RX(PI / 2)), 0.45)
	_add(box(0.5, 0.14, 4.0), dark, T(0, -R + 0.02, -0.2), 0.8)
	# Conning tower with a hatch, a window strip and a periscope.
	_add(box(1.0, 0.9, 1.4), color, T(0, R + 0.35, -0.1), 0.4)
	_add(cyl(0.32, 0.32, 0.08, 10), white, T(0, R + 0.83, -0.25), 0.5)
	_add(box(0.55, 0.2, 0.06), dark, T(0, R + 0.55, 0.6), 0.3)
	_add(cyl(0.06, 0.06, 0.95, 8), steel, T(0.28, R + 1.25, -0.4), 0.3, 0.7)
	_add(box(0.13, 0.13, 0.4), steel, T(0.28, R + 1.72, -0.25), 0.3, 0.7)
	_add(cyl(0.05, 0.05, 0.03, 8), pal("glass"), T(0.28, R + 1.72, -0.04, RX(PI / 2)), 0.15)
	# Side portholes: white rim, deep-blue glass.
	for sx in [-1.0, 1.0]:
		_add(cyl(0.34, 0.34, 0.1, 10), white, T(sx * 0.9, 0.22, -0.5, RZ(PI / 2)), 0.5)
		_add(cyl(0.25, 0.25, 0.14, 10), pal("porthole"), T(sx * 0.9, 0.22, -0.5, RZ(PI / 2)), 0.15)
	# Cockpit bubble forward of the tower: white collar, cockpit floor.
	var dome_z := 1.7
	var collar_y := R - 0.05
	_add(cyl(0.7, 0.74, 0.5, 10), white, T(0, collar_y, dome_z), 0.45)
	_add(cyl(0.6, 0.6, 0.06, 10), dark, T(0, collar_y + 0.25, dome_z), 0.8)
	# Lower rudder (fixed), prop shroud and its cross.
	_add(box(0.07, 0.75, 0.6), white, T(0, -0.95, -2.5), 0.5)
	_add(torus(0.66, 0.06, 4, 12), dark, T(0, 0, -3.05, RX(PI / 2)), 0.7)
	_add(box(0.05, 0.6, 0.08), dark, T(0, 0.35, -3.05), 0.7)
	_add(box(0.05, 0.6, 0.08), dark, T(0, -0.35, -3.05), 0.7)
	_add(box(0.6, 0.05, 0.08), dark, T(0.35, 0, -3.05), 0.7)
	_add(box(0.6, 0.05, 0.08), dark, T(-0.35, 0, -3.05), 0.7)
	# Headlight housings; the wheel the kid holds.
	for sx in [-1.0, 1.0]:
		_add(cyl(0.23, 0.23, 0.1, 8), dark, T(sx * 0.42, 0.3, 2.78, RX(PI / 2)), 0.6)
	_add(torus(0.15, 0.025, 4, 10), dark, T(0, collar_y + 0.08 + 0.3, dome_z - 0.05 + 0.34, RX(PI / 2 - 0.4)), 0.5)
	# Dome rim.
	_add(torus(0.7, 0.06, 4, 14), white, T(0, collar_y + 0.27, dome_z), 0.45)
	_flush("Hull", self)

	# Emissive lamp discs (own material so the glow can be hot).
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = pal("cream")
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.91, 0.67)
	lamp_mat.emission_energy_multiplier = 6.0
	lamp_mat.roughness = 0.3
	var lamps_st := SurfaceTool.new()
	lamps_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1.0, 1.0]:
		lamps_st.append_from(cyl(0.17, 0.17, 0.06, 8), 0, T(sx * 0.42, 0.3, 2.85, RX(PI / 2)))
	var lamps_mesh := lamps_st.commit()
	lamps_mesh.surface_set_material(0, lamp_mat)
	var lamps_mi := MeshInstance3D.new()
	lamps_mi.name = "Lamps"
	lamps_mi.mesh = lamps_mesh
	add_child(lamps_mi)
	triangles += lamps_mesh.get_faces().size() / 3

	# Stern planes (tilt with dive) and the upper rudder (swings with steer).
	_add(box(1.1, 0.07, 0.6), white, T(-0.9, 0, 0), 0.5)
	_add(box(1.1, 0.07, 0.6), white, T(0.9, 0, 0), 0.5)
	_planes = _flush("Planes", self, T(0, 0, -2.5))
	_add(box(0.07, 0.8, 0.6), white, T(0, 0, -0.2), 0.5)
	_rudder = _flush("Rudder", self, T(0, 1.0, -2.3))

	# Propeller in the shroud.
	_add(cyl(0.12, 0.16, 0.3, 8), steel, T(0, 0, 0, RX(PI / 2)), 0.3, 0.75)
	for k in 4:
		var xf := Transform3D(RZ(k * PI / 2) * RY(0.65), Vector3.ZERO) * T(0, 0.38, 0)
		_add(box(0.16, 0.5, 0.05), steel, xf, 0.3, 0.75)
	_prop = _flush("Prop", self, T(0, 0, -3.15))

	# Glass dome (transparent) over the cockpit.
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	dome.mesh = sphere(0.72, 12, 5, true)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = pal("glass")
	glass.albedo_color.a = 0.26
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.08
	glass.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	dome.material_override = glass
	dome.position = Vector3(0, collar_y + 0.25, dome_z)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	triangles += dome.mesh.get_faces().size() / 3

	# The kid.
	_kid = Node3D.new()
	_kid.name = "Kid"
	_kid.position = Vector3(0, collar_y + 0.08, dome_z - 0.05)
	add_child(_kid)
	_build_kid(pal(HELMETS[color_index]), pal("yellow") if color_index == 1 else pal("orange"))

	# Headlights: spot lights plus soft translucent cones that fade in under water.
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.albedo_color = Color(1.0, 0.96, 0.88, 0.0)
	_cone_mat.emission_enabled = true
	_cone_mat.emission = Color(1.0, 0.96, 0.85)
	_cone_mat.emission_energy_multiplier = 0.8
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mat.no_depth_test = false
	_cone_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var cone_mesh := cyl(0.0, 1.5, 9.0, 10)
	cone_mesh.cap_bottom = false
	cone_mesh.cap_top = false
	for sx in [-1.0, 1.0]:
		var cone := MeshInstance3D.new()
		cone.name = "Cone%s" % ("L" if sx < 0 else "R")
		cone.mesh = cone_mesh
		cone.material_override = _cone_mat
		cone.transform = T(sx * 0.42, 0.3, 2.85, RY(-sx * 0.05)) * T(0, 0, 4.5, RX(-PI / 2))
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cone)
		triangles += cone_mesh.get_faces().size() / 3
		var lamp := SpotLight3D.new()
		lamp.name = "Lamp%s" % ("L" if sx < 0 else "R")
		lamp.position = Vector3(sx * 0.42, 0.3, 2.85)
		lamp.rotation.y = PI - sx * 0.05
		lamp.light_color = Color(1.0, 0.93, 0.78)
		lamp.light_energy = 0.0
		lamp.spot_range = 24.0
		lamp.spot_angle = 26.0
		lamp.spot_attenuation = 0.8
		lamp.shadow_enabled = false
		add_child(lamp)
		_lamps.append(lamp)

	_build_bubbles()
	built = true


func _build_kid(helmet: Color, vest: Color) -> void:
	var shirt := pal("white")
	var skin := pal("skin")
	var dark := pal("dark")
	_add(box(0.32, 0.42, 0.22), shirt, T(0, 0.22, 0), 0.6)
	_add(box(0.38, 0.34, 0.3), vest, T(0, 0.24, 0), 0.6)
	_add(box(0.08, 0.26, 0.04), shirt, T(0, 0.24, 0.15), 0.6)
	_add(cyl(0.06, 0.06, 0.1, 6), skin, T(0, 0.46, 0), 0.7)
	var hands := [Vector3(-0.17, 0.3, 0.3), Vector3(0.17, 0.3, 0.3)]
	var shoulders := [Vector3(-0.2, 0.38, 0.02), Vector3(0.2, 0.38, 0.02)]
	for i in 2:
		var sh: Vector3 = shoulders[i]
		var hd: Vector3 = hands[i]
		var dir := hd - sh
		var len := dir.length()
		var q := Quaternion(Vector3.UP, dir / len)
		_add(cyl(0.05, 0.042, len, 6), shirt, Transform3D(Basis(q), sh) * T(0, len / 2, 0), 0.6)
		_add(sphere(0.06, 5, 3), skin, T(hd.x, hd.y, hd.z), 0.7)
	_torso = _flush("Torso", _kid)
	_add(sphere(0.19, 8, 5), skin, T(0, 0, 0), 0.7)
	_add(sphere(0.215, 8, 4, true), helmet, T(0, 0.02, 0), 0.35)
	_add(box(0.3, 0.035, 0.14), dark, T(0, -0.005, 0.2), 0.4)
	_add(sphere(0.03, 5, 3), dark, T(-0.07, 0, 0.175), 0.3)
	_add(sphere(0.03, 5, 3), dark, T(0.07, 0, 0.175), 0.3)
	_head = _flush("Head", _torso, T(0, 0.52, 0))


func _build_bubbles() -> void:
	_bubbles = GPUParticles3D.new()
	_bubbles.name = "Bubbles"
	_bubbles.position = Vector3(0, 0, -3.3)
	_bubbles.amount = 150
	_bubbles.lifetime = BUBBLE_LIFE
	_bubbles.local_coords = false
	_bubbles.emitting = false
	_bubbles.fixed_fps = 30
	_bubbles.interpolate = true
	_bubbles.visibility_aabb = AABB(Vector3(-12, -8, -12), Vector3(24, 16, 24))
	_bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.35, 0.05)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.55
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.24, 0)
	pm.scale_min = 0.022
	pm.scale_max = 0.057
	pm.color_initial_ramp = DeepMesh._noise_ramp(4242)
	_bubbles.process_material = pm
	_bubble_mat = ShaderMaterial.new()
	_bubble_mat.shader = load("res://shaders/underwater_bubbles.gdshader")
	_bubble_mat.set_shader_parameter("life", BUBBLE_LIFE)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _bubble_mat
	_bubbles.draw_pass_1 = quad
	add_child(_bubbles)


# ------------------------------------------------------------------- update
## Animate from the body (SubPhysics or anything with the same fields).
func update(dt: float, body) -> void:
	var k := 1.0 - exp(-dt * 6.0)
	_dive += (float(body.dive) - _dive) * k
	_steer += (float(body.steer) - _steer) * k
	_throttle += (float(body.throttle) - _throttle) * (1.0 - exp(-dt * 3.0))
	_spin += dt * (1.5 + 34.0 * absf(_throttle)) * (1.0 if _throttle >= 0.0 else -1.0)
	_prop.rotation.z = _spin
	_planes.rotation.x = -_dive * 0.5
	_rudder.rotation.y = _steer * 0.55
	var speed_k := minf(1.0, float(body.speed) / float(body.hull.max_speed))
	_lean += ((-float(body.steer) * 0.25) * (0.4 + 0.6 * speed_k) - _lean) * (1.0 - exp(-dt * 5.0))
	_torso.rotation.z = _lean
	_head.rotation.z = _lean * 0.7
	_head.rotation.y = -_lean * 0.8
	var sub := float(body.submersion)
	_cone_mat.albedo_color.a = 0.12 * sub
	for lamp in _lamps:
		lamp.light_energy = 3.0 * sub
		lamp.visible = sub > 0.02
	# Bubbles from the stern while the prop is turning under water.
	var surface := float(body.surface_y)
	_bubble_mat.set_shader_parameter("surface_y", surface)
	var fwd: Vector3 = body.forward
	var stern_y: float = body.position.y - fwd.y * 3.2
	var rate := (40.0 * absf(_throttle) + 3.0 * sub) if stern_y < surface - 0.3 else 0.0
	_bubbles.emitting = rate > 0.5
	_bubbles.amount_ratio = clampf(rate / 43.0, 0.05, 1.0)
