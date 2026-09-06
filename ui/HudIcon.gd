class_name HudIcon
extends Control
## Vector icons of the web HUD (Hud.js ICON table) drawn with CanvasItem primitives so the
## HUD needs no textures. `paint()` is static so buttons and badges can draw icons inline.

const INK := Color("05324f")

@export var icon := "play":
	set(v):
		icon = v
		queue_redraw()
@export var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
@export var ink := INK:
	set(v):
		ink = v
		queue_redraw()


func _draw() -> void:
	paint(self, icon, Rect2(Vector2.ZERO, size), color, ink)


## Rotate around the centre (next-gate arrow).
func set_angle(rad: float) -> void:
	pivot_offset = size * 0.5
	rotation = rad


# --------------------------------------------------------------------------- primitives
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, col, w, true)
	ci.draw_circle(a, w * 0.5, col)
	ci.draw_circle(b, w * 0.5, col)


static func _path(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, closed := false) -> void:
	var p := pts
	if closed:
		p = pts.duplicate()
		p.append(pts[0])
	ci.draw_polyline(p, col, w, true)
	for q in pts:
		ci.draw_circle(q, w * 0.5, col)


static func _fill(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(pts, col)
	var p := pts.duplicate()
	p.append(pts[0])
	ci.draw_polyline(p, col, 1.2, true)


static func _arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	ci.draw_arc(c, r, a0, a1, 24, col, w, true)
	ci.draw_circle(c + Vector2(cos(a0), sin(a0)) * r, w * 0.5, col)
	ci.draw_circle(c + Vector2(cos(a1), sin(a1)) * r, w * 0.5, col)


static func _rect(ci: CanvasItem, x: float, y: float, w: float, h: float, col: Color, rad := 0.0) -> void:
	if rad > 0.0:
		ci.draw_colored_polygon(HudPanel.rrect_points(Rect2(x, y, w, h), rad, 4), col)
	else:
		ci.draw_rect(Rect2(x, y, w, h), col)


static func _pv(arr: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(arr.size() / 2)
	for i in p.size():
		p[i] = Vector2(arr[i * 2], arr[i * 2 + 1])
	return p


## Draw `icon` fitted inside `rect`. `color` is the main colour, `ink` the dark accent.
static func paint(ci: CanvasItem, icon: String, rect: Rect2, color: Color, ink: Color) -> void:
	var unit := Vector2(24, 24)
	match icon:
		"chevron", "left", "right", "up", "down", "star", "wheel":
			unit = Vector2(100, 100)
		"pedal":
			unit = Vector2(80, 140)
	var s := minf(rect.size.x / unit.x, rect.size.y / unit.y)
	var off := rect.position + (rect.size - unit * s) * 0.5
	ci.draw_set_transform(off, 0.0, Vector2(s, s))
	match icon:
		"flag":
			_line(ci, Vector2(4, 2), Vector2(4, 22), color, 2.2)
			_fill(ci, _pv([5, 3, 19, 3, 16.5, 7.5, 19, 12, 5, 12]), color)
			for q in [[5, 3], [12, 3], [8.5, 6], [15.5, 6], [5, 9], [12, 9]]:
				_rect(ci, q[0], q[1], 3.5, 3, ink)
		"lap":
			_arc(ci, Vector2(12, 12), 9, -PI * 0.5, -PI * 2.0, color, 3)
			_fill(ci, _pv([21, 4, 21, 10, 15, 10]), color)
		"clock":
			ci.draw_arc(Vector2(12, 13), 8.5, 0, TAU, 40, color, 3, true)
			_path(ci, _pv([12, 8, 12, 13, 15.5, 15]), color, 3)
			_line(ci, Vector2(9, 2), Vector2(15, 2), color, 3)
		"chevron":
			var p := _pv([50, 4, 90, 48, 66, 48, 66, 94, 34, 94, 34, 48, 10, 48])
			_path(ci, p, ink, 7, true)
			_fill(ci, p, color)
		"camera":
			_fill(ci, _pv([2, 10, 4, 8, 8, 8, 10, 5, 14, 5, 16, 8, 20, 8, 22, 10, 22, 19, 20, 21, 4, 21, 2, 19]), color)
			ci.draw_circle(Vector2(12, 14), 3.5, ink)
			ci.draw_circle(Vector2(12, 14), 1.6, color)
		"pause":
			_rect(ci, 5, 4, 5, 16, color, 1.5)
			_rect(ci, 14, 4, 5, 16, color, 1.5)
		"water":
			var p := PackedVector2Array([Vector2(12, 3)])
			for i in 25:
				var a := deg_to_rad(-52.0 + 284.0 * float(i) / 24.0)
				p.append(Vector2(12, 15) + Vector2(cos(a), sin(a)) * 7.0)
			_fill(ci, p, color)
			_arc(ci, Vector2(12, 15.5), 2.5, PI, PI * 0.5, ink, 1.8)
		"home":
			_path(ci, _pv([3, 11.5, 12, 4, 21, 11.5]), color, 3)
			_rect(ci, 6, 10.5, 12, 9.5, color)
			_rect(ci, 10, 14, 4, 6, ink)
		"play":
			_fill(ci, _pv([7, 4.5, 7, 19.5, 20, 12]), color)
		"reset":
			_arc(ci, Vector2(12, 12), 8, 0.0, deg_to_rad(314.5), color, 3.2)
			_fill(ci, _pv([20, 3, 20, 9, 14, 9]), color)
		"sound", "muted":
			_fill(ci, _pv([3, 9, 7, 9, 12, 5, 12, 19, 7, 15, 3, 15]), color)
			if icon == "sound":
				_arc(ci, Vector2(15.5, 12), 5, -PI * 0.5, PI * 0.5, color, 2.6)
				_arc(ci, Vector2(12.28, 12), 9, deg_to_rad(-46.2), deg_to_rad(46.2), color, 2.6)
			else:
				_line(ci, Vector2(16, 9), Vector2(21, 15), color, 2.8)
				_line(ci, Vector2(21, 9), Vector2(16, 15), color, 2.8)
		"full":
			_path(ci, _pv([4, 9, 4, 4, 9, 4]), color, 3)
			_path(ci, _pv([15, 4, 20, 4, 20, 9]), color, 3)
			_path(ci, _pv([20, 15, 20, 20, 15, 20]), color, 3)
			_path(ci, _pv([9, 20, 4, 20, 4, 15]), color, 3)
		"bolt":
			var p := _pv([13, 2, 4, 14, 11, 14, 10, 22, 19, 10, 12, 10])
			_path(ci, p, ink, 1.6, true)
			_fill(ci, p, color)
		"horn":
			_fill(ci, _pv([3, 10, 3, 14, 4, 15, 7, 15, 16, 19, 16, 5, 7, 9, 4, 9]), color)
			_arc(ci, Vector2(15.88, 12), 4, deg_to_rad(-38.7), deg_to_rad(38.7), color, 2.6)
			_path(ci, _pv([6, 15, 6, 20, 7.5, 21.5, 9, 20, 9, 16]), color, 2.4)
		"left":
			_path(ci, _pv([66, 12, 30, 50, 66, 88]), color, 18)
		"right":
			_path(ci, _pv([34, 12, 70, 50, 34, 88]), color, 18)
		"up":
			_path(ci, _pv([12, 66, 50, 30, 88, 66]), color, 18)
		"down":
			_path(ci, _pv([12, 34, 50, 70, 88, 34]), color, 18)
		"star":
			var p := _pv([50, 6, 63.5, 33.6, 94, 38, 72, 59.4, 77.2, 90, 50, 75.5, 22.8, 90, 28, 59.4, 6, 38, 36.5, 33.6])
			_path(ci, p, ink, 6, true)
			_fill(ci, p, color)
		"tilt":
			var c := Vector2(10, 12)
			var rot := deg_to_rad(-14.0)
			var p := PackedVector2Array()
			for q in [Vector2(4, 3), Vector2(16, 3), Vector2(16, 21), Vector2(4, 21)]:
				p.append(c + (q - c).rotated(rot))
			_path(ci, p, color, 2.4, true)
			_arc(ci, Vector2(14.06, 13.22), 6, -1.058, 0.131, color, 2.4)
		"wheel":
			var c := Vector2(50, 50)
			ci.draw_arc(c, 42, 0, TAU, 64, ink, 16, true)
			ci.draw_arc(c, 42, 0, TAU, 64, Color("ffd84d"), 10, true)
			for sp in [Vector2(50, 18), Vector2(22, 66), Vector2(78, 66)]:
				_line(ci, c, sp, ink, 12)
			for sp in [Vector2(50, 18), Vector2(22, 66), Vector2(78, 66)]:
				_line(ci, c, sp, Color("ffb42e"), 6)
			ci.draw_circle(c, 13, ink)
			ci.draw_circle(c, 8, Color("ff9f1a"))
			ci.draw_circle(Vector2(50, 13), 5.5, ink)
			ci.draw_circle(Vector2(50, 13), 4.5, Color.WHITE)
		"pedal":
			_rect(ci, 10, 6, 60, 128, Color(0, 0, 0, 0.28), 16)
			for i in 5:
				_rect(ci, 22, 22 + 20 * i, 36, 8, Color(1, 1, 1, 0.55), 4)
		"anchor":
			ci.draw_arc(Vector2(12, 4.6), 2.2, 0, TAU, 20, color, 1.8, true)
			_line(ci, Vector2(12, 6.8), Vector2(12, 20.6), color, 2.4)
			_line(ci, Vector2(8, 9.6), Vector2(16, 9.6), color, 2.4)
			_arc(ci, Vector2(12, 13.2), 7.2, deg_to_rad(22.0), deg_to_rad(158.0), color, 2.6)
			_fill(ci, _pv([4.9, 14.6, 7.6, 15.4, 5.6, 17.6]), color)
			_fill(ci, _pv([19.1, 14.6, 16.4, 15.4, 18.4, 17.6]), color)
		"stop":
			_rect(ci, 5, 5, 14, 14, color, 2.5)
		_:
			ci.draw_arc(Vector2(12, 12), 8, 0, TAU, 32, color, 2.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
