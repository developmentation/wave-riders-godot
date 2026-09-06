extends SceneTree
## Headless layout validator for worlds/Worlds.gd (port of tools/check-worlds.mjs).
##
##   godot --headless --path . -s tools/check-worlds.gd [world-id] [--no-maps] [--strict]
##
## Rules: gates in open water (terrain below the web's -1.5 m across the gate line with a 12 m
## margin and along the corridor to the next gate; below OPEN_WATER = -4 m across the half-width,
## a warning unless --strict), spaced 120-250 m (or
## def.gate_spacing), no turn over 100 deg between consecutive gates, start and portals in open
## water, portals >= 40 m from every gate, <= 40 palms and <= 8000 terrain triangles per island.
## Draws a top-down map of each world to tools/shots/map-<world>.png. Exit code 1 on failure.

const WorldsDef := preload("res://worlds/Worlds.gd")
const Field := preload("res://worlds/IslandField.gd")

const OPEN_WATER := -4.0        # metres of seabed under the keel counts as open water (gate line)
const SHALLOW := -1.5           # the web's threshold, applied with the 12 m margin and to corridors
const MIN_GAP := 120.0
const MAX_GAP := 250.0
const MAX_TURN := 100.0
const MIN_PORTAL_GATE := 40.0
const MAP_PX := 360

var failures := 0
var strict := false
var _fields: Array = []
var _piers: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	var maps := true
	for a in args:
		if a == "--no-maps":
			maps = false
		elif a == "--strict":
			strict = true
		elif not a.begins_with("--"):
			only = a
	# also accept the world id as a plain trailing arg before `--`
	for a in OS.get_cmdline_args():
		if WorldsDef.WORLDS.has(a):
			only = a
	var t0 := Time.get_ticks_msec()
	for id in WorldsDef.WORLDS.keys():
		if only != "" and only != id:
			continue
		_check_world(id, WorldsDef.WORLDS[id], maps)
	print("")
	print("%d failure(s)" % failures if failures else "all worlds pass (%d ms)" % (Time.get_ticks_msec() - t0))
	quit(1 if failures else 0)


func _fail(w: String, msg: String) -> void:
	failures += 1
	print("  FAIL [%s] %s" % [w, msg])


func _ok(msg: String) -> void:
	print("  ok   " + msg)


func _height(x: float, z: float) -> float:
	var h := Field.fields_height(_fields, x, z)
	for p in _piers:
		h = maxf(h, Field.pier_height(p, x, z))
	return h


## Worst (highest) terrain inside a disc.
func _clear(x: float, z: float, r: float, step := 2.0) -> float:
	var worst := -INF
	var dx := -r
	while dx <= r:
		var dz := -r
		while dz <= r:
			if dx * dx + dz * dz <= r * r:
				worst = maxf(worst, _height(x + dx, z + dz))
			dz += step
		dx += step
	return worst


func _check_world(id: String, def: Dictionary, maps: bool) -> void:
	print("")
	print("== %s (%s) ==" % [id, def.name])
	_fields = []
	for isl in def.islands:
		_fields.append(Field.new(isl))
	_piers = def.get("piers", [])

	# islands
	for f in _fields:
		if f.tris > Field.MAX_TRIS:
			_fail(id, "island seed %d: %d terrain triangles (> %d)" % [f.def.seed, f.tris, Field.MAX_TRIS])
		if int(f.def.palms) > Field.MAX_PALMS:
			_fail(id, "island seed %d: %d palms (> %d)" % [f.def.seed, f.def.palms, Field.MAX_PALMS])
		print("  island seed %d %s R%d h%d: grid %dx%d, %d tris, palms %d, centre h %.1f" % [
			f.def.seed, f.shape, int(f.def.radius), int(f.def.height), f.nu, f.nv, f.tris, int(f.def.palms), f.sample(f.def.x, f.def.z)])

	# start
	var s: Dictionary = def.start
	var sh := _clear(s.x, s.z, 14.0)
	if sh > SHALLOW:
		_fail(id, "start at (%s,%s) is not in open water (terrain %.2f m)" % [s.x, s.z, sh])
	else:
		_ok("start (%s, %s) heading %d deg, seabed %.1f m" % [s.x, s.z, int(rad_to_deg(s.heading)), sh])

	# gates
	var G: Array = def.gates
	var lap := 0.0
	var gaps: Array[float] = []
	var turns: Array[float] = []
	for i in G.size():
		var g: Dictionary = G[i]
		var n: Dictionary = G[(i + 1) % G.size()]
		var fx := sin(g.heading)
		var fz := cos(g.heading)
		var hw: float = g.width / 2.0
		# the gate line itself: strict depth across the half-width, the web's threshold with a 12 m margin
		var worst_in := -INF
		var worst_margin := -INF
		var t := -hw - 12.0
		while t <= hw + 12.0:
			var h := _height(g.x - fz * t, g.z + fx * t)
			worst_margin = maxf(worst_margin, h)
			if absf(t) <= hw:
				worst_in = maxf(worst_in, h)
			t += 2.0
		if worst_in > OPEN_WATER:
			# keel clearance: the web layouts were designed against SHALLOW, so this is advisory
			# unless --strict (swell gate 6 sits over the -2.8 m shelf of the west island)
			if strict:
				_fail(id, "gate %d at (%s,%s): terrain %.2f m inside the half-width (want < %.1f)" % [i, g.x, g.z, worst_in, OPEN_WATER])
			else:
				print("  WARN [%s] gate %d at (%s,%s): terrain %.2f m inside the half-width (keel clearance target %.1f)" % [id, i, g.x, g.z, worst_in, OPEN_WATER])
		if worst_margin > SHALLOW:
			_fail(id, "gate %d at (%s,%s) touches land (terrain %.2f m within 12 m of the gate line)" % [i, g.x, g.z, worst_margin])
		if G.size() < 2:
			continue
		# spacing to the next gate
		var dx: float = n.x - g.x
		var dz: float = n.z - g.z
		var dist := sqrt(dx * dx + dz * dz)
		lap += dist
		gaps.append(dist)
		var band: Array = def.get("gate_spacing", [MIN_GAP, MAX_GAP])
		if dist < band[0] or dist > band[1]:
			_fail(id, "gate %d -> %d: spacing %d m (want %d-%d)" % [i, (i + 1) % G.size(), int(dist), int(band[0]), int(band[1])])
		# turn: heading change, and bearing to the next gate vs both headings
		var bearing := atan2(dx, dz)
		var turn := absf(rad_to_deg(Field.wrap_pi(n.heading - g.heading)))
		var off1 := absf(rad_to_deg(Field.wrap_pi(bearing - g.heading)))
		var off2 := absf(rad_to_deg(Field.wrap_pi(n.heading - bearing)))
		turns.append(turn)
		if turn > MAX_TURN:
			_fail(id, "gate %d -> %d: heading change %d deg (> %d)" % [i, (i + 1) % G.size(), int(turn), int(MAX_TURN)])
		if off1 > MAX_TURN * 0.7 or off2 > MAX_TURN * 0.7:
			_fail(id, "gate %d -> %d: next gate is %d/%d deg off axis" % [i, (i + 1) % G.size(), int(off1), int(off2)])
		# corridor: straight chord between the gates, as wide as the gate
		var cw := -INF
		var steps := int(ceil(dist / 4.0))
		for k in steps + 1:
			var tt := float(k) / steps
			var cx: float = g.x + dx * tt
			var cz: float = g.z + dz * tt
			var px := -dz / dist
			var pz := dx / dist
			var w: float = (g.width * (1.0 - tt) + n.width * tt) / 2.0
			for o in [-w, -w / 2.0, 0.0, w / 2.0, w]:
				cw = maxf(cw, _height(cx + px * o, cz + pz * o))
		if cw > SHALLOW:
			_fail(id, "corridor gate %d -> %d crosses land (terrain %.2f m)" % [i, (i + 1) % G.size(), cw])
	if not G.is_empty():
		_ok("%d gates, lap %d m by chords (%d m along the curve), laps %d" % [G.size(), int(lap), int(def.get("lap_length", 0)), def.laps])
		if not gaps.is_empty():
			print("  spacing min %d max %d m; turn max %d deg" % [int(gaps.min()), int(gaps.max()), int(turns.max())])
		var first: Dictionary = G[0]
		var d_s := Vector2(first.x - s.x, first.z - s.z).length()
		if d_s < 40.0 or d_s > 260.0:
			_fail(id, "first gate is %d m from the start" % int(d_s))

	# portals
	for p in def.portals:
		var ph := _clear(p.x, p.z, 10.0)
		if ph > SHALLOW:
			_fail(id, "portal -> %s at (%s,%s) is not in open water (terrain %.2f m)" % [p.dest, p.x, p.z, ph])
		for i in G.size():
			var d := Vector2(G[i].x - p.x, G[i].z - p.z).length()
			if d < MIN_PORTAL_GATE:
				_fail(id, "portal -> %s is %d m from gate %d (want >= %d)" % [p.dest, int(d), i, int(MIN_PORTAL_GATE)])
		if not WorldsDef.WORLDS.has(p.dest):
			if p.dest in WorldsDef.EXTERNAL_DESTS:
				print("  note portal dest '%s' is an external world (submarine module)" % p.dest)
			else:
				_fail(id, "portal dest '%s' is not a world" % p.dest)
		var d0 := Vector2(p.x - s.x, p.z - s.z).length()
		if id != "hub" and (d0 < 40.0 or d0 > 200.0):
			_fail(id, "return portal is %d m from the start (want 40-200)" % int(d0))
	_ok("%d portal(s)" % def.portals.size())

	# weather sanity
	if not def.weather.has("key") or not WorldsDef.CONDITIONS.has(def.weather.key):
		_fail(id, "weather.key missing or unknown")
	if not def.has("water") or not def.water.has("scatter") or not def.water.has("absorb"):
		_fail(id, "water scatter/absorb missing")

	if maps:
		_draw_map(id, def)


# -------------------------------------------------------------- map PNG
func _draw_map(id: String, def: Dictionary) -> void:
	var W := MAP_PX
	var H := MAP_PX
	var R: float = def.bounds * 1.05
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for j in H:
		var z := (1.0 - float(j) / (H - 1) * 2.0) * R
		for i in W:
			var x := (float(i) / (W - 1) * 2.0 - 1.0) * R
			var h := _height(x, z)
			var c: Color
			if h <= SHALLOW:
				var t := clampf((h - Field.DEEP) / (SHALLOW - Field.DEEP), 0.0, 1.0)   # 0 deep .. 1 shallow
				c = Color((10.0 + 60.0 * t) / 255.0, (60.0 + 140.0 * t) / 255.0, (120.0 + 110.0 * t) / 255.0)
			elif h <= 1.4:
				c = Color(240.0 / 255.0, 222.0 / 255.0, 160.0 / 255.0)
			else:
				var t := minf(1.0, h / 45.0)
				c = Color((70.0 - 30.0 * t) / 255.0, (180.0 - 90.0 * t) / 255.0, (60.0 - 20.0 * t) / 255.0)
			img.set_pixel(i, j, c)
	var to_px := func(x: float, z: float) -> Vector2i:
		return Vector2i(int(round((x / R + 1.0) * 0.5 * (W - 1))), int(round((1.0 - (z / R + 1.0) * 0.5) * (H - 1))))
	var put := func(p: Vector2i, c: Color) -> void:
		if p.x >= 0 and p.y >= 0 and p.x < W and p.y < H:
			img.set_pixelv(p, c)
	var line := func(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
		var a: Vector2i = to_px.call(x0, z0)
		var b: Vector2i = to_px.call(x1, z1)
		var n := maxi(maxi(absi(b.x - a.x), absi(b.y - a.y)), 1)
		for k in n + 1:
			put.call(Vector2i(int(round(a.x + (b.x - a.x) * float(k) / n)), int(round(a.y + (b.y - a.y) * float(k) / n))), c)
	var disc := func(x: float, z: float, r: int, c: Color) -> void:
		var a: Vector2i = to_px.call(x, z)
		for i in range(-r, r + 1):
			for j in range(-r, r + 1):
				if i * i + j * j <= r * r:
					put.call(a + Vector2i(i, j), c)
	# grid rings every 250 m
	var rr := 250.0
	while rr < R:
		for a in 720:
			var ang := float(a) / 720.0 * TAU
			put.call(to_px.call(cos(ang) * rr, sin(ang) * rr), Color.WHITE)
		rr += 250.0
	var G: Array = def.gates
	var green := Color(40.0 / 255.0, 1.0, 80.0 / 255.0)
	for i in G.size():
		var g: Dictionary = G[i]
		var n: Dictionary = G[(i + 1) % G.size()]
		line.call(g.x, g.z, n.x, n.z, Color.WHITE)
	for i in G.size():
		var g: Dictionary = G[i]
		var fx := sin(g.heading)
		var fz := cos(g.heading)
		line.call(g.x - fz * g.width / 2.0, g.z + fx * g.width / 2.0, g.x + fz * g.width / 2.0, g.z - fx * g.width / 2.0, green)
		line.call(g.x, g.z, g.x + fx * 30.0, g.z + fz * 30.0, green)
		disc.call(g.x, g.z, 3 if i == 0 else 2, green)
	var magenta := Color(1.0, 60.0 / 255.0, 1.0)
	for p in def.portals:
		disc.call(p.x, p.z, 3, magenta)
		line.call(p.x, p.z, p.x + sin(p.heading) * 40.0, p.z + cos(p.heading) * 40.0, magenta)
	var s: Dictionary = def.start
	var yellow := Color(1.0, 230.0 / 255.0, 40.0 / 255.0)
	disc.call(s.x, s.z, 3, yellow)
	line.call(s.x, s.z, s.x + sin(s.heading) * 45.0, s.z + cos(s.heading) * 45.0, yellow)
	for f in _fields:
		disc.call(f.def.x, f.def.z, 1, Color.BLACK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var file := "res://tools/shots/map-%s.png" % id
	img.save_png(file)
	print("  map -> %s  (%d m half-width, rings every 250 m)" % [ProjectSettings.globalize_path(file), int(R)])
