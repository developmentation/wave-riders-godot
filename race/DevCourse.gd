class_name DevCourse
## Test courses laid on the bare sea, ported from the web dev harnesses (Race.js / SubRace.js
## devInstall): a rounded-rectangle loop of 8 gates for boats and a descending spiral of 8 hoops
## for submarines. Main.gd uses them for `--skip=devcourse` / `--skip=devspiral` and, when worlds/
## is missing, for any race world id, so the race flow can be tested before islands exist.

const IDS := ["devcourse", "devspiral"]


static func has(id: String) -> bool:
	return IDS.has(id)


static func build(id: String) -> Dictionary:
	return spiral() if id == "devspiral" else loop()


## Rounded rectangle 420 x 260 m with 80 m corners, sampled by arc length; start 14 m behind gate 0.
static func loop() -> Dictionary:
	var A := 420.0
	var B := 260.0
	var R := 80.0
	var pts: Array = []
	var corners := [[A / 2 - R, B / 2 - R], [-(A / 2 - R), B / 2 - R], [-(A / 2 - R), -(B / 2 - R)], [A / 2 - R, -(B / 2 - R)]]
	for c in 4:
		var cx: float = corners[c][0]
		var cz: float = corners[c][1]
		for k in 11:
			var a := (c * PI / 2) + (k / 10.0) * (PI / 2)
			pts.append(Vector2(cx + cos(a) * R, cz + sin(a) * R))
	var n := pts.size()
	var len: Array = [0.0]
	for i in range(1, n + 1):
		var p: Vector2 = pts[i % n]
		var q: Vector2 = pts[i - 1]
		len.append(float(len[i - 1]) + p.distance_to(q))
	var total: float = len[n]
	var at := func(s: float) -> Vector2:
		s = fposmod(s, total)
		var i := 0
		while i < n - 1 and float(len[i + 1]) < s:
			i += 1
		var t := (s - float(len[i])) / maxf(1e-6, float(len[i + 1]) - float(len[i]))
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % n]
		return p + (q - p) * t
	var gates: Array = []
	var N := 8
	var s0: float = float(len[32]) + (A - 2 * R) * 0.5
	for i in N:
		var s := s0 + (float(i) / N) * total
		var p: Vector2 = at.call(s)
		var p2: Vector2 = at.call(s + 2.0)
		gates.append({"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1), "heading": atan2(p2.x - p.x, p2.y - p.y), "width": 24.0})
	var g0: Dictionary = gates[0]
	var start := {"x": g0.x - sin(g0.heading) * 14.0, "z": g0.z - cos(g0.heading) * 14.0, "heading": g0.heading}
	return {"id": "devcourse", "name": "Test Loop", "start": start, "gates": gates, "laps": 3, "bounds": 900.0, "portals": [],
		"weather": {"swell_hs": 0.3, "swell_period": 8.0, "wind_speed": 4.0, "foam": 0.35}}


## 8 hoops on a 110 m circle, descending from -2 to -40 m; the seabed is `ground` (a Callable) or -60.
static func spiral(ground: Callable = Callable(), cx := 0.0, cz := 0.0) -> Dictionary:
	var N := 8
	var R := 110.0
	var gates: Array = []
	for i in N:
		var a := (float(i) / N) * TAU
		var x := cx + sin(a) * R
		var z := cz + cos(a) * R
		var heading := atan2(cos(a), -sin(a))
		var y := -2.0 - 38.0 * (float(i) / (N - 1))
		var g := -60.0
		if ground.is_valid():
			g = ground.call(x, z)
		y = minf(maxf(y, g + 8.0), -2.0)
		gates.append({"x": snappedf(x, 0.1), "y": snappedf(y, 0.1), "z": snappedf(z, 0.1), "heading": heading, "width": 14.0})
	var g0: Dictionary = gates[0]
	var start := {"x": g0.x - sin(g0.heading) * 16.0, "y": -0.5, "z": g0.z - cos(g0.heading) * 16.0, "heading": g0.heading}
	return {"id": "devspiral", "name": "Test Spiral", "start": start, "gates": gates, "laps": 3, "bounds": 900.0, "portals": [],
		"underwater": true, "seabed": -60.0, "weather": {"swell_hs": 0.4, "swell_period": 8.0}}
