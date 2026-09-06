class_name Wake
extends Node3D
## Boat wake — port of src/game/Wake.js: a foam ribbon laid along the stern's
## path, a hull foam skirt hugging the waterline outline, and one pooled spray
## system per boat (bow sheets, chine sheets, wave-slap bursts, rooster tail).
##
## The ribbon is a strip of N rows. A row is dropped every few tenths of a
## metre of travel and remembers where the stern was, which way was starboard,
## how hard the boat was working and how far it had travelled. Each frame the
## rows are re-widened along the Kelvin half-angle (19.47 deg) from the distance
## the boat has since covered, snapped onto the sampled sea so the foam rides
## the waves, and faded over ~4 s. While the hull is airborne the ribbon ends at
## the last row it laid in the water.
##
## Three draw calls per boat: ribbon (ImmediateMesh), skirt (ImmediateMesh) and
## spray: a pooled MultiMesh of billboard quads. Each sprite is written once at
## spawn (position, velocity, birth time, life, size, seed, kind packed into its
## instance transform) and the vertex shader integrates it analytically
## (ballistic fall + exponential horizontal drag), so the CPU only touches a slot
## when a sprite is born or dies. The node is top_level: world space throughout.

const ROWS := 48                       # stored stern samples
const LIFE := 4.0                      # seconds a row stays visible
const MIN_SPACING := 0.6               # metres of travel between rows
const KELVIN := 0.35357                # tan(19.47 deg)
const SPRAY_MAX := 360                 # pooled sprites per boat
const G := 9.81
const ROOSTER_KMH := 40.0
const SURF_LIFT := 0.10                # ribbon sits this far above the sampled sea
const SKIRT_SEG := 24                  # outline samples around the hull
const SKIRT_RINGS := 3                 # under the hull, on the outline, outer edge
const SKIRT_LIFT := 0.10               # skirt lift at Hs 0 (+0.09 m per metre of Hs)
const SKIRT_V := [0.0, 0.4, 1.0]       # across-coordinate of each ring for the shader

const FOAM_COMMON := """
uniform sampler2D foam_tex : repeat_enable, filter_linear_mipmap;
varying vec3 world_pos;
varying vec4 data;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	data = vec4(UV, UV2);
}
"""

const RIBBON_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
""" + FOAM_COMMON + """
void fragment() {
	float u = abs(data.x);
	float age = data.y;
	float strength = data.z;
	float core = data.w;              // fraction of the half-width the hull churn occupies
	float age_fade = 1.0 - age;
	// Kelvin arms: two diverging foam lines near the strip edges; they lose
	// their foam within a couple of seconds while the hull churn lingers.
	float arms = smoothstep(0.64, 0.82, u) * (1.0 - smoothstep(0.90, 1.0, u)) * pow(age_fade, 2.2) * 0.95;
	// Hull churn: the aerated stripe behind the transom, hull-wide.
	float churn = (1.0 - smoothstep(core * 0.55, core * 1.25, u)) * pow(age_fade, 0.7);
	// Fresh sheet between them right behind the boat so the V has a root.
	float sheet = (1.0 - smoothstep(0.0, 0.9, u)) * 0.2 * pow(age_fade, 3.0);
	float density = (churn + arms + sheet) * strength;
	if (density < 0.19) { discard; }
	// Foam texture in world space so it stays put while the boat moves on.
	vec4 fx = texture(foam_tex, world_pos.xz * 0.16 + vec2(TIME * 0.004, -TIME * 0.003));
	vec4 fx2 = texture(foam_tex, world_pos.xz * 0.55 - vec2(TIME * 0.012, TIME * 0.009));
	float clusters = fx.r * 0.6 + fx2.r * 0.4;
	float bubbles = fx2.g * 0.6 + fx.g * 0.4;
	float dissolve = fx.a * 0.6 + fx2.a * 0.4;
	// The deposited density is carved by the raft texture and the survival
	// threshold rises with age, so old foam breaks into scattered rafts.
	float noise = smoothstep(0.22, 0.80, dissolve * 0.5 + clusters * 0.5);
	float carved = density * (0.25 + noise * 1.15);
	float onset = 0.26 + age * 0.40;
	float foam = smoothstep(onset, onset + 0.30, carved);
	foam *= mix(0.35, 1.0, bubbles);
	if (foam < 0.004) { discard; }
	ALBEDO = vec3(0.93, 0.96, 0.985) * (1.0 + 0.3 * churn * age_fade + 0.25 * bubbles);
	ROUGHNESS = 0.9;
	ALPHA = clamp(foam, 0.0, 1.0) * 0.96;
}
"""

const SKIRT_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
""" + FOAM_COMMON + """
void fragment() {
	float v = data.x;
	float strength = data.z;
	float pulse = data.w;
	float around = cos(data.y * 6.2831853);      // 1 at the stem, -1 at the transom
	// Solid where it tucks under the hull, dissolving outward. The bow quarter
	// throws the most water at speed; the transom churn is always there.
	float body = 1.0 - smoothstep(0.40, 1.0, v);
	float bow = smoothstep(0.2, 1.0, around) * (0.08 + 0.30 * strength);
	float stern = smoothstep(0.3, 1.0, -around) * (0.10 + 0.20 * strength);
	float density = body * (0.28 + 0.60 * strength + bow + stern + pulse * 0.6);
	if (density < 0.08) { discard; }
	vec4 fx = texture(foam_tex, world_pos.xz * 0.30 + vec2(TIME * 0.02, -TIME * 0.015));
	vec4 fx2 = texture(foam_tex, world_pos.xz * 0.95 - vec2(TIME * 0.05, TIME * 0.035));
	float clusters = fx.r * 0.55 + fx2.r * 0.45;
	float bubbles = fx2.g * 0.6 + fx.g * 0.4;
	float dissolve = fx.a * 0.5 + fx2.a * 0.5;
	float noise = smoothstep(0.14, 0.78, dissolve * 0.5 + clusters * 0.5);
	// Carve hard: the raft texture must open holes through the sheet or the
	// skirt reads as a white cut-out around the hull instead of froth on water.
	float carved = density * (0.18 + noise * 1.25);
	float onset = 0.24 + v * 0.42;
	float foam = smoothstep(onset, onset + 0.30, carved);
	foam *= mix(0.30, 1.0, bubbles);
	// wet edge: a thin aerated veil hugging the hull that never fully clears
	float veil = (1.0 - smoothstep(0.22, 0.60, v)) * (0.20 + 0.35 * strength) * (0.35 + 0.65 * noise);
	float a = max(foam, veil);
	if (a < 0.004) { discard; }
	ALBEDO = vec3(0.93, 0.96, 0.985) * (1.0 + 0.25 * bubbles + 0.25 * pulse + 0.15 * bow);
	ROUGHNESS = 0.9;
	ALPHA = clamp(a, 0.0, 1.0) * 0.86;
}
"""

## Spray sprite: camera-facing quad sized in metres, capped in screen pixels, lit
## as an upward-facing raft so it matches the foam around it.
## INSTANCE_CUSTOM = (size m, age01, seed, kind).
const SPRAY_DRAW := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
uniform float clock = 0.0;
varying vec4 pdata;
void vertex() {
	// Packed per instance: origin = spawn position, column 0 = spawn velocity,
	// column 1 = (birth time, life, size), column 2 = (seed, kind, -).
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	float life = max(MODEL_MATRIX[1].y, 0.05);
	float t = clamp(clock - MODEL_MATRIX[1].x, 0.0, life);
	float age = t / life;
	float seed = MODEL_MATRIX[2].x;
	float kind = MODEL_MATRIX[2].y;
	// horizontal velocity decays as exp(-0.9 t); vertical is ballistic
	float k = (1.0 - exp(-0.9 * t)) / 0.9;
	vec3 origin = p0 + vec3(v0.x * k, v0.y * t - 0.5 * 9.81 * t * t, v0.z * k);
	pdata = vec4(MODEL_MATRIX[1].z, age, seed, kind);
	// grow a little with age: a sheet of droplets disperses as it flies
	float size = pdata.x * (1.0 + age * 0.9);
	float dist = max(length((VIEW_MATRIX * vec4(origin, 1.0)).xyz), 0.5);
	// cap in screen terms (40 px at 720p) so close sprites cannot swamp the fill budget
	// abs(): Godot's Vulkan projection flips Y, so [1][1] is negative
	float px = size * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / dist;
	float px_c = clamp(px, 1.5, 40.0 * VIEWPORT_SIZE.y / 720.0);
	size = (px > 1e-5) ? size * px_c / px : 0.0;
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(origin, 1.0));
	MODELVIEW_MATRIX = mv * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX);
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// slightly irregular blob so a cloud of them does not read as bubbles
	float d = length(q + 0.18 * vec2(sin(pdata.z * 31.0), cos(pdata.z * 17.0)));
	if (d > 1.0) { discard; }
	float age = pdata.y;
	float shape = pow(1.0 - d * d, 1.9);
	float fade = smoothstep(0.0, 0.08, age) * pow(1.0 - age, 1.1);
	float a = shape * fade * mix(0.40, 0.26, pdata.w);
	ALBEDO = vec3(0.95, 0.97, 1.0);
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _foam_tex: ImageTexture = null
static var _ribbon_mat: ShaderMaterial = null
static var _skirt_mat: ShaderMaterial = null
static var _spray_mat: ShaderMaterial = null
## Global switches (quality presets / debugging): spray sprites, wake ribbon, hull skirt.
static var spray_enabled := true
static var ribbon_enabled := true
static var skirt_enabled := true
## Shared spray clock (seconds of game time), advanced once per frame by whichever wake runs first.
static var clock := 0.0
static var _clock_frame := -1

## The BoatPhysics this wake trails. Defaults to the parent node.
var body: Node = null
var hs := 0.0
## Boats farther than this from the camera rebuild their ribbon/skirt every other
## frame (they are a few pixels wide; the sea samples are what cost).
var lod_distance := 45.0
var _lod_skip := false

var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _skirt: MeshInstance3D
var _skirt_mesh: ImmediateMesh
var _spray: MultiMeshInstance3D
var _spray_mm: MultiMesh
var _spray_buf: PackedFloat32Array

# spray pool: instance slots packed alive-first; only births and deaths touch the buffer
var _die: PackedFloat32Array
var _alive := 0
var _spray_dirty := false

# ribbon rows (ring buffer, oldest first)
var _rx: PackedFloat32Array
var _rz: PackedFloat32Array
var _rrx: PackedFloat32Array
var _rrz: PackedFloat32Array
var _rdist: PackedFloat32Array
var _rtime: PackedFloat32Array
var _rstr: PackedFloat32Array
var _head := 0
var _count := 0
var _dist := 0.0
var _last_lay := -1e9
var _time := 0.0
var _w0 := 1.0
var _planing := false

# skirt outline in hull space (+z forward, +x starboard)
var _olx: PackedFloat32Array
var _olz: PackedFloat32Array
var _onx: PackedFloat32Array
var _onz: PackedFloat32Array
var _skirt_base := 1.0
var _skirt_str := 0.0
var _pulse := 0.0

# spray accumulators
var _hull_ready := false
var _emit_acc := 0.0
var _chine_acc := 0.0
var _rooster_acc := 0.0
var _prev_slap := 0.0

var _f := Vector3(0, 0, 1)
var _r := Vector3(1, 0, 0)
var _s := Vector3.ZERO


static func _ensure_shared() -> void:
	if _foam_tex != null:
		return
	# Foam raft texture: r = clusters, g = fine bubbles, a = dissolve mask.
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var clusters := FastNoiseLite.new()
	clusters.noise_type = FastNoiseLite.TYPE_CELLULAR
	clusters.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	clusters.frequency = 0.045
	clusters.seed = 7
	var bubbles := FastNoiseLite.new()
	bubbles.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bubbles.fractal_octaves = 3
	bubbles.frequency = 0.16
	bubbles.seed = 3
	var dissolve := FastNoiseLite.new()
	dissolve.noise_type = FastNoiseLite.TYPE_PERLIN
	dissolve.fractal_octaves = 4
	dissolve.frequency = 0.03
	dissolve.seed = 11
	# Tile: sample on a torus-mapped domain so the texture repeats seamlessly.
	for y in n:
		for x in n:
			var a := float(x) / n * TAU
			var b := float(y) / n * TAU
			var px := (cos(a) + 1.0) * 40.0
			var py := (sin(a) + 1.0) * 40.0
			var pz := (cos(b) + 1.0) * 40.0
			var pw := (sin(b) + 1.0) * 40.0
			var c := clampf(clusters.get_noise_3d(px, py, pz + pw) * 0.5 + 0.5, 0.0, 1.0)
			var bb := clampf(bubbles.get_noise_3d(px + 100.0, py, pz + pw) * 0.5 + 0.5, 0.0, 1.0)
			var dd := clampf(dissolve.get_noise_3d(px, py + 100.0, pz + pw) * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, bb, 0.0, dd))
	img.generate_mipmaps()
	_foam_tex = ImageTexture.create_from_image(img)

	var sh := Shader.new()
	sh.code = RIBBON_SHADER
	_ribbon_mat = ShaderMaterial.new()
	_ribbon_mat.shader = sh
	_ribbon_mat.set_shader_parameter("foam_tex", _foam_tex)
	_ribbon_mat.render_priority = 1
	sh = Shader.new()
	sh.code = SKIRT_SHADER
	_skirt_mat = ShaderMaterial.new()
	_skirt_mat.shader = sh
	_skirt_mat.set_shader_parameter("foam_tex", _foam_tex)
	_skirt_mat.render_priority = 2      # after the ribbon it grows out of, before the airborne spray
	sh = Shader.new()
	sh.code = SPRAY_DRAW
	_spray_mat = ShaderMaterial.new()
	_spray_mat.shader = sh
	_spray_mat.render_priority = 3


func _ready() -> void:
	top_level = true
	transform = Transform3D.IDENTITY
	if body == null and get_parent() is BoatPhysics:
		body = get_parent()
	_ensure_shared()
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.name = "Ribbon"
	_ribbon.mesh = _ribbon_mesh
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	_skirt_mesh = ImmediateMesh.new()
	_skirt = MeshInstance3D.new()
	_skirt.name = "Skirt"
	_skirt.mesh = _skirt_mesh
	_skirt.material_override = _skirt_mat
	_skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_skirt)
	_spray_mm = MultiMesh.new()
	_spray_mm.transform_format = MultiMesh.TRANSFORM_3D
	_spray_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)     # `size` is the sprite diameter, like the web's point sprites
	_spray_mm.mesh = quad
	_spray_mm.instance_count = SPRAY_MAX
	_spray_mm.visible_instance_count = 0
	_spray_buf.resize(SPRAY_MAX * 16)
	_die.resize(SPRAY_MAX)
	_spray = MultiMeshInstance3D.new()
	_spray.name = "Spray"
	_spray.multimesh = _spray_mm
	_spray.material_override = _spray_mat
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.ignore_occlusion_culling = true
	add_child(_spray)

	_rx.resize(ROWS); _rz.resize(ROWS); _rrx.resize(ROWS); _rrz.resize(ROWS)
	_rdist.resize(ROWS); _rtime.resize(ROWS); _rstr.resize(ROWS)
	_olx.resize(SKIRT_SEG); _olz.resize(SKIRT_SEG); _onx.resize(SKIRT_SEG); _onz.resize(SKIRT_SEG)
	if body != null:
		_setup_hull()


func _setup_hull() -> void:
	var hull: Dictionary = body.hull
	_w0 = float(hull.width) * 0.55
	_planing = float(hull.get("planing", 0.0)) >= 0.8
	# Superellipse outline: pointier forward (n = 1.6) than aft (n = 3.0) so
	# the ring reads as a boat, not a pill.
	var half_w := float(hull.width) * 0.5
	var half_l := float(hull.length) * 0.5
	for s in SKIRT_SEG:
		var th := float(s) / SKIRT_SEG * TAU
		var c := cos(th)
		var sn := sin(th)
		var n := 1.6 if c > 0.0 else 3.0
		var e := 2.0 / n
		var lx := half_w * signf(sn) * pow(absf(sn), e)
		var lz := half_l * signf(c) * pow(absf(c), e)
		var nx := lx / (half_w * half_w)
		var nz := lz / (half_l * half_l)
		var len := maxf(Vector2(nx, nz).length(), 1e-6)
		_olx[s] = lx
		_olz[s] = lz
		_onx[s] = nx / len
		_onz[s] = nz / len
	_skirt_base = 0.40 + 0.30 * float(hull.width)   # metres outward at rest
	_hull_ready = true


func _sea_h(x: float, z: float) -> float:
	return body.sea_height(x, z)


func _lay(x: float, z: float, rxv: float, rzv: float, strength: float) -> void:
	var i := (_head + _count) % ROWS
	if _count == ROWS:
		_head = (_head + 1) % ROWS
	else:
		_count += 1
	_rx[i] = x; _rz[i] = z; _rrx[i] = rxv; _rrz[i] = rzv
	_rdist[i] = _dist; _rtime[i] = _time; _rstr[i] = strength


func _process(dt: float) -> void:
	if body == null or dt <= 0.0:
		return
	if not _hull_ready:
		_setup_hull()
	var frame := Engine.get_process_frames()
	if frame != _clock_frame:
		_clock_frame = frame
		clock += dt
		_spray_mat.set_shader_parameter("clock", clock)
	hs = body.sea_hs()
	# distance LOD: far boats refresh the foam meshes at half rate (time still advances)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.distance_to(body.position) > lod_distance:
		_lod_skip = not _lod_skip
		if _lod_skip:
			_time += dt
			_dist += float(body.speed) * dt
			clock_only_reap()
			return
	update(dt)


## Cheap frame for far boats: only drop dead spray sprites so the pool does not fill.
func clock_only_reap() -> void:
	var changed := false
	var i := 0
	while i < _alive:
		if _die[i] <= clock:
			_alive -= 1
			if i != _alive:
				var src := _alive * 16
				var dst := i * 16
				for k in 16:
					_spray_buf[dst + k] = _spray_buf[src + k]
				_die[i] = _die[_alive]
			changed = true
			continue
		i += 1
	if changed:
		_spray_mm.buffer = _spray_buf
		_spray_mm.visible_instance_count = _alive
		_spray.visible = _alive > 0


func update(dt: float) -> void:
	var b := body
	var hull: Dictionary = b.hull
	var L := float(hull.length)
	var W := float(hull.width)
	_time += dt
	var speed: float = b.speed
	_dist += speed * dt
	_f = b.forward
	_f.y = 0.0
	if _f.length_squared() < 1e-6:
		_f = Vector3(0, 0, 1)
	_f = _f.normalized()
	_r = Vector3(_f.z, 0.0, -_f.x)            # starboard
	var bpos: Vector3 = b.position
	# stern on the waterline
	_s = bpos + _f * (-L * 0.5)
	var submersion: float = b.submersion
	var wake_strength: float = b.wake_strength
	var wet := 1.0 if submersion > 0.0 else 0.0

	# ---- lay a new row every MIN_SPACING m, coarser at speed so 48 rows span LIFE seconds
	var spacing := maxf(MIN_SPACING, speed * LIFE / ROWS)
	var strength := clampf(wake_strength * 1.6 + smoothstep(0.8, 4.0, speed) * 0.35, 0.0, 1.0) * wet
	if _dist - _last_lay >= spacing and speed > 0.6 and strength > 0.03:
		_lay(_s.x, _s.z, _r.x, _r.z, strength)
		_last_lay = _dist
	# drop rows that have faded or fallen far behind
	while _count > 0 and (_time - _rtime[_head] >= LIFE or _dist - _rdist[_head] > 90.0):
		_head = (_head + 1) % ROWS
		_count -= 1

	# ---- rebuild ribbon: stored rows oldest -> newest, then the live stern
	var rows := _count + (1 if (_count > 0 and submersion > 0.0) else 0)
	_ribbon_mesh.clear_surfaces()
	if rows > 1 and ribbon_enabled:
		var pv: PackedVector3Array = []
		var pd: PackedVector4Array = []
		pv.resize(rows * 3)
		pd.resize(rows * 3)
		var v := 0
		for k in _count:
			var i := (_head + k) % ROWS
			var age := (_time - _rtime[i]) / LIFE
			var behind := _dist - _rdist[i]
			var half := _w0 + behind * KELVIN
			var core := minf(1.0, _w0 * 1.25 / half)
			for side in [-1.0, 0.0, 1.0]:
				var x: float = _rx[i] + _rrx[i] * half * side
				var z: float = _rz[i] + _rrz[i] * half * side
				pv[v] = Vector3(x, _sea_h(x, z) + SURF_LIFT, z)
				pd[v] = Vector4(side, age, _rstr[i], core)
				v += 1
		if submersion > 0.0:
			# live head at the transom so the wake is glued to the hull
			for side in [-1.0, 0.0, 1.0]:
				var x: float = _s.x + _r.x * _w0 * side
				var z: float = _s.z + _r.z * _w0 * side
				pv[v] = Vector3(x, _sea_h(x, z) + SURF_LIFT, z)
				pd[v] = Vector4(side, 0.0, strength, 1.0)
				v += 1
		_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for rrow in rows - 1:
			var a := rrow * 3
			# three vertices per row (port, centre, starboard): two quads per row pair
			_quad(_ribbon_mesh, pv, pd, a, a + 3, a + 4, a + 1)
			_quad(_ribbon_mesh, pv, pd, a + 1, a + 4, a + 5, a + 2)
		_ribbon_mesh.surface_end()
	_ribbon.visible = rows > 1

	# ---- hull foam skirt
	# strength eases in and out so a hull skipping off a crest does not flicker
	var str_target := wet * clampf(0.22 + wake_strength * 0.9 + smoothstep(1.0, 9.0, speed) * 0.5, 0.0, 1.0)
	_skirt_str += (str_target - _skirt_str) * minf(1.0, dt * (5.0 if str_target < _skirt_str else 8.0))
	_pulse = maxf(_pulse * exp(-dt * 3.0), float(b.slap_impulse))
	var k_str := _skirt_str
	var k_pulse := minf(1.0, _pulse)
	_skirt.visible = k_str > 0.02 and skirt_enabled
	_skirt_mesh.clear_surfaces()
	if _skirt.visible:
		var outer := _skirt_base * (0.7 + 0.55 * k_str + 0.8 * k_pulse)
		# In a big sea the drawn surface can stand above the sampled one: lift the skirt with Hs.
		var lift := minf(0.45, SKIRT_LIFT + 0.09 * hs)
		# planing bow rides clear of the water: pull the forward part of the ring aft with pitch
		var bow_up := clampf(float(b.forward.y), 0.0, 0.4)
		var kp: PackedVector3Array = []
		var kd: PackedVector4Array = []
		kp.resize(SKIRT_SEG * SKIRT_RINGS)
		kd.resize(SKIRT_SEG * SKIRT_RINGS)
		var k := 0
		for r in SKIRT_RINGS:
			var vv: float = SKIRT_V[r]
			# ring 0 is tucked under the hull so the paint straddles the intersection line
			var scale := 0.68 if r == 0 else 1.02
			var out := outer if r == SKIRT_RINGS - 1 else 0.0
			for s in SKIRT_SEG:
				var lz := _olz[s] * scale + _onz[s] * out
				var lx := _olx[s] * scale + _onx[s] * out
				if lz > 0.0:
					lz *= 1.0 - bow_up * 0.9
				var x := bpos.x + _r.x * lx + _f.x * lz
				var z := bpos.z + _r.z * lx + _f.z * lz
				kp[k] = Vector3(x, _sea_h(x, z) + lift, z)
				kd[k] = Vector4(vv, float(s) / SKIRT_SEG, k_str, k_pulse)
				k += 1
		_skirt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in SKIRT_RINGS - 1:
			for s in SKIRT_SEG:
				var s1 := (s + 1) % SKIRT_SEG
				var a := r * SKIRT_SEG + s
				var bb := r * SKIRT_SEG + s1
				var c := (r + 1) * SKIRT_SEG + s
				var d := (r + 1) * SKIRT_SEG + s1
				_quad(_skirt_mesh, kp, kd, a, c, d, bb)
		_skirt_mesh.surface_end()

	# ---- spray emission
	if not spray_enabled:
		return
	var kmh: float = b.speed_kmh
	var bow_rate := 75.0 * smoothstep(3.0, 13.0, speed) * (0.5 + 0.5 * wake_strength) * wet
	_emit_acc += bow_rate * dt
	while _emit_acc >= 1.0:
		_emit_acc -= 1.0
		# a sheet peels off the chine from the stem back to midships
		for side in [-1.0, 1.0]:
			_emit_bow(side, speed, L, W, 0.0, randf() * 0.8)
	# low, wide sheets skimming off both chines: these wrap the hull edges in white at speed
	_chine_acc += 80.0 * smoothstep(3.5, 14.0, speed) * (0.6 + 0.4 * wake_strength) * wet * dt
	while _chine_acc >= 1.0:
		_chine_acc -= 1.0
		for side in [-1.0, 1.0]:
			_emit_chine(side, speed, L, W)
	if _planing and kmh > ROOSTER_KMH and submersion > 0.0:
		_rooster_acc += 45.0 * smoothstep(ROOSTER_KMH, ROOSTER_KMH + 35.0, kmh) * dt
		while _rooster_acc >= 1.0:
			_rooster_acc -= 1.0
			_emit_rooster(speed, L)
	var slap: float = b.slap_impulse
	if slap > _prev_slap + 0.15:
		var n := mini(60, roundi(28.0 * slap + 10.0))
		for i in n:
			_emit_bow(1.0 if (i & 1) else -1.0, maxf(speed, 4.0), L, W, 1.0, float(i) / n * 1.6 - 0.8)
	_prev_slap = slap

	# ---- spray: reap dead sprites (swap-remove keeps the alive ones packed first)
	var i := 0
	while i < _alive:
		if _die[i] <= clock:
			_alive -= 1
			if i != _alive:
				var src := _alive * 16
				var dst := i * 16
				for k in 16:
					_spray_buf[dst + k] = _spray_buf[src + k]
				_die[i] = _die[_alive]
			_spray_dirty = true
			continue
		i += 1
	if _spray_dirty:
		_spray_dirty = false
		_spray_mm.buffer = _spray_buf
		_spray_mm.visible_instance_count = _alive
		# the sprites fly in world space: keep a generous box around the boat
		_spray.custom_aabb = AABB(bpos - Vector3(60, 30, 60), Vector3(120, 60, 120))
	_spray.visible = _alive > 0


func _quad(m: ImmediateMesh, pv: PackedVector3Array, pd: PackedVector4Array, a: int, b: int, c: int, d: int) -> void:
	# Godot flips the normal of back faces under cull_disabled, so wind every quad
	# clockwise seen from above (Godot's front face) or the foam is lit from below.
	var order := [a, b, c, a, c, d]
	if (pv[b] - pv[a]).cross(pv[c] - pv[a]).y > 0.0:
		order = [a, c, b, a, d, c]
	for i in order:
		var dd := pd[i]
		m.surface_set_normal(Vector3.UP)
		m.surface_set_uv(Vector2(dd.x, dd.y))
		m.surface_set_uv2(Vector2(dd.z, dd.w))
		m.surface_add_vertex(pv[i])


func _spawn(pos: Vector3, vel: Vector3, life: float, size: float, kind: float) -> void:
	if _alive >= SPRAY_MAX:
		return
	var o := _alive * 16
	# 3x4 rows: column 0 = velocity, column 1 = (birth, life, size), column 2 = (seed, kind, 0), column 3 = position
	_spray_buf[o] = vel.x; _spray_buf[o + 1] = clock; _spray_buf[o + 2] = randf(); _spray_buf[o + 3] = pos.x
	_spray_buf[o + 4] = vel.y; _spray_buf[o + 5] = life; _spray_buf[o + 6] = kind; _spray_buf[o + 7] = pos.y
	_spray_buf[o + 8] = vel.z; _spray_buf[o + 9] = size; _spray_buf[o + 10] = 0.0; _spray_buf[o + 11] = pos.z
	_spray_buf[o + 12] = 0.0; _spray_buf[o + 13] = 0.0; _spray_buf[o + 14] = 0.0; _spray_buf[o + 15] = 0.0
	_die[_alive] = clock + life
	_alive += 1
	_spray_dirty = true


## Spray peeling off one side of the hull. `along` (0 = stem, 1 = stern)
## slides the emitter down the chine; the sheet is thrown highest at the stem.
func _emit_bow(side: float, speed: float, L: float, W: float, kind: float, along := 0.0) -> void:
	var a := clampf(along, -0.5, 1.0)
	var fwd := L * (0.42 - a * 0.9)
	var beam := W * ((0.25 + a * 1.2) if a < 0.15 else 0.43)
	var p: Vector3 = body.position + _f * fwd + _r * (side * beam)
	p.y = _sea_h(p.x, p.z) + 0.05
	var r1 := randf()
	var r2 := randf()
	var r3 := randf()
	var stem := 1.0 - maxf(a, 0.0) * 0.6
	var out := (1.4 + speed * 0.17) * (0.6 + r1 * 0.8) * (1.0 + kind * 0.8)
	var up := (1.2 + speed * 0.16) * (0.5 + r2 * 0.9) * stem * (1.0 + kind * 1.2)
	var along_v := speed * (0.5 + r3 * 0.25) * (1.0 - kind * 0.3)
	_spawn(p, Vector3(_f.x * along_v + _r.x * side * out + (r2 - 0.5) * 0.8, up, _f.z * along_v + _r.z * side * out + (r1 - 0.5) * 0.8),
		0.5 + r3 * 0.5 + kind * 0.3, (0.34 + r1 * 0.42) * (1.0 + kind * 0.6) * sqrt(W / 2.3), kind)


## Chine spray: a flat sheet skimming sideways off the hull between the stem
## and midships. Low and short-lived, so it stays glued to the waterline.
func _emit_chine(side: float, speed: float, L: float, W: float) -> void:
	var r1 := randf()
	var r2 := randf()
	var r3 := randf()
	var a := 0.05 + r3 * 0.55                         # 0 = stem .. 1 = stern
	var fwd := L * (0.42 - a * 0.9)
	var beam := W * ((0.30 + a * 1.0) if a < 0.15 else 0.46)
	var p: Vector3 = body.position + _f * fwd + _r * (side * beam)
	p.y = _sea_h(p.x, p.z) + 0.03
	var out := (0.9 + speed * 0.11) * (0.6 + r1 * 0.7)
	var up := (0.35 + speed * 0.045) * (0.4 + r2 * 0.8)
	var along := speed * (0.55 + r2 * 0.2)
	_spawn(p, Vector3(_f.x * along + _r.x * side * out + (r2 - 0.5) * 0.5, up, _f.z * along + _r.z * side * out + (r1 - 0.5) * 0.5),
		0.28 + r3 * 0.30, (0.28 + r1 * 0.34) * sqrt(W / 2.3), 0.5)


## Rooster tail: a narrow column thrown up behind the transom by the drive.
func _emit_rooster(speed: float, L: float) -> void:
	var p: Vector3 = body.position + _f * (-L * 0.52)
	p.y = _sea_h(p.x, p.z) + 0.1
	var r1 := randf()
	var r2 := randf()
	var r3 := randf()
	var along := speed * (0.30 + r1 * 0.2)
	var up := 3.0 + speed * 0.20 * (0.5 + r2)
	var side := (r3 - 0.5) * 1.6
	_spawn(p, Vector3(_f.x * along + _r.x * side, up, _f.z * along + _r.z * side), 0.6 + r2 * 0.4, 0.3 + r1 * 0.35, 1.0)
