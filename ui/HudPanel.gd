class_name HudPanel
extends Control
## Rounded gradient panel with a white border, hard drop shadow, soft shadow and inner
## highlight — the look of the web HUD's .wr-badge / .wr-card / .wr-hint boxes. The static
## helpers are shared by HudButton, HudBadge and the boat cards.

const INK := Color("05324f")

@export var stops: Array[Color] = [Color(0.055, 0.275, 0.478, 0.88), Color(0.016, 0.118, 0.22, 0.92)]
@export var radius := 24.0
@export var border := 4.0
@export var border_color := Color.WHITE
@export var drop := 6.0
@export var drop_color := Color(0, 0, 0, 0.3)
@export var soft := 24.0
@export var soft_alpha := 0.35
@export var highlight := 0.4
## Extra rounded-rectangle "glow ring" drawn around the panel (selected card).
@export var ring := 0.0
@export var ring_color := Color(1, 0.847, 0.302, 0.35)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(size.x, size.y - drop))
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	if ring > 0.0:
		var rr := r.grow(ring)
		draw_colored_polygon(rrect_points(rr, radius + ring), ring_color)
	draw_panel(self, r, radius, stops, border, border_color, drop, drop_color, soft, soft_alpha, highlight)


# ----------------------------------------------------------------------------- geometry
static func rrect_points(r: Rect2, radius: float, segs := 7) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if rad <= 0.5:
		pts.append(r.position)
		pts.append(r.position + Vector2(r.size.x, 0))
		pts.append(r.end)
		pts.append(r.position + Vector2(0, r.size.y))
		return pts
	var centers := [
		r.position + Vector2(rad, rad),
		r.position + Vector2(r.size.x - rad, rad),
		r.end - Vector2(rad, rad),
		r.position + Vector2(rad, r.size.y - rad),
	]
	var start := PI
	for c in centers:
		for i in segs + 1:
			var a: float = start + (PI * 0.5) * float(i) / float(segs)
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		start += PI * 0.5
	return dedupe(pts)


## Clip a convex polygon to the horizontal band ya <= y <= yb (Sutherland–Hodgman).
static func clip_band(pts: PackedVector2Array, ya: float, yb: float) -> PackedVector2Array:
	var out := _clip_half(pts, ya, true)
	return _clip_half(out, yb, false)


static func _clip_half(pts: PackedVector2Array, y: float, keep_below: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n == 0:
		return out
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var ina := (a.y >= y) if keep_below else (a.y <= y)
		var inb := (b.y >= y) if keep_below else (b.y <= y)
		if ina:
			out.append(a)
		if ina != inb:
			var t := (y - a.y) / (b.y - a.y)
			out.append(a.lerp(b, t))
	return dedupe(out)


## Drop consecutive (near-)duplicate points; the triangulator rejects them.
static func dedupe(pts: PackedVector2Array, eps := 0.05) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > eps * eps:
			out.append(p)
	if out.size() > 2 and out[0].distance_squared_to(out[out.size() - 1]) <= eps * eps:
		out.resize(out.size() - 1)
	return out


## Fill a convex polygon with a vertical gradient. `stops` are evenly spaced top→bottom.
static func draw_gradient_poly(ci: CanvasItem, pts: PackedVector2Array, stops: Array, y0: float, y1: float) -> void:
	if pts.size() < 3:
		return
	var ns := stops.size()
	if ns == 1:
		ci.draw_colored_polygon(pts, stops[0])
		return
	var h := maxf(y1 - y0, 0.001)
	for s in ns - 1:
		var ya := y0 + h * float(s) / float(ns - 1)
		var yb := y0 + h * float(s + 1) / float(ns - 1)
		var band := clip_band(pts, ya - 0.01, yb + 0.01)
		if band.size() < 3:
			continue
		var cols := PackedColorArray()
		cols.resize(band.size())
		var ca: Color = stops[s]
		var cb: Color = stops[s + 1]
		for i in band.size():
			var t := clampf((band[i].y - ya) / maxf(yb - ya, 0.001), 0.0, 1.0)
			cols[i] = ca.lerp(cb, t)
		ci.draw_polygon(band, cols)


static func draw_soft_shadow(ci: CanvasItem, r: Rect2, radius: float, spread: float, alpha: float, dy: float) -> void:
	if spread <= 0.0 or alpha <= 0.0:
		return
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var layers := 4
	for i in layers:
		var t := float(i) / float(layers)
		var g := spread * (1.0 - t)
		var rr := Rect2(r.position + Vector2(0, dy), r.size).grow(g)
		ci.draw_colored_polygon(rrect_points(rr, radius + g), Color(0, 0, 0, alpha * 0.3 * (0.4 + 0.6 * t)))


static func stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, closed := true) -> void:
	if pts.size() < 2:
		return
	var p := pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
		p.append(pts[1])
	ci.draw_polyline(p, col, w, true)


static func draw_panel(ci: CanvasItem, r: Rect2, radius: float, stops: Array, border: float, border_color: Color,
		drop: float, drop_color: Color, soft: float, soft_alpha: float, highlight: float) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var body := rrect_points(r, radius)
	if soft > 0.0:
		draw_soft_shadow(ci, r, radius, soft, soft_alpha, drop + soft * 0.4)
	if drop > 0.0:
		ci.draw_colored_polygon(rrect_points(Rect2(r.position + Vector2(0, drop), r.size), radius), drop_color)
	draw_gradient_poly(ci, body, stops, r.position.y, r.end.y)
	if border > 0.0:
		stroke(ci, rrect_points(r.grow(-border * 0.5), maxf(radius - border * 0.5, 0.0)), border_color, border)
	if highlight > 0.0:
		var inset := border + maxf(1.5, border * 0.35)
		var inner := rrect_points(r.grow(-inset), maxf(radius - inset, 0.0))
		var limit := r.position.y + inset + maxf(radius - inset, 0.0) * 0.55 + 0.5
		var seg := PackedVector2Array()
		# The top arc of the inset rounded rect: the points run TL corner → TR corner first.
		var started := false
		for p in inner:
			if p.y <= limit and (not started or seg.size() > 0):
				seg.append(p)
				started = true
			elif started and seg.size() > 0 and p.y > limit:
				break
		if seg.size() >= 2:
			ci.draw_polyline(seg, Color(1, 1, 1, highlight), maxf(1.5, border * 0.55), true)
