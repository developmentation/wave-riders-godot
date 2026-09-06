class_name HudSpeedo
extends Control
## Round km/h dial of the web HUD (Hud.js speedoSvg): radial-gradient face, blue/yellow/red
## arcs, ticks and labels, red needle with a dark hub and the big yellow digit.

const MAX_KMH := 120.0
const SWEEP := 240.0
const START := -120.0
const INK := Color("05324f")

var value := 0.0:
	set(v):
		v = maxf(v, 0.0)
		if absf(v - value) > 0.05:
			value = v
			queue_redraw()
var _face: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color("0d4f86"))
	g.set_color(1, Color("041e35"))
	_face = GradientTexture2D.new()
	_face.gradient = g
	_face.fill = GradientTexture2D.FILL_RADIAL
	_face.fill_from = Vector2(0.5, 0.42)
	_face.fill_to = Vector2(0.5, 1.04)
	_face.width = 128
	_face.height = 128


static func _polar(c: Vector2, r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg - 90.0)
	return c + Vector2(cos(a), sin(a)) * r


func _angle(v: float) -> float:
	return START + SWEEP * clampf(v / MAX_KMH, 0.0, 1.03)


func _draw() -> void:
	var s := minf(size.x, size.y) / 200.0
	var off := (size - Vector2(200, 200) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))
	var c := Vector2(100, 100)
	# drop + soft shadow
	for i in 3:
		draw_circle(c + Vector2(0, 8 + i * 4), 96 + i * 3, Color(0, 0, 0, 0.16 - i * 0.04))
	draw_circle(c + Vector2(0, 8), 96, Color(0, 0, 0, 0.3))
	# face: radial gradient clipped to a circle
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n := 64
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := c + Vector2(cos(a), sin(a)) * 96.0
		pts.append(p)
		uvs.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.5)
	draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, _face)
	draw_arc(c, 96, 0, TAU, 96, Color.WHITE, 5, true)
	draw_arc(c, 88, 0, TAU, 96, Color(1, 1, 1, 0.14), 1.5, true)
	# coloured arcs (Godot angles: 0 = +x, clockwise positive; our 0° = top)
	var a0 := deg_to_rad(_angle(0) - 90.0)
	var a70 := deg_to_rad(_angle(70) - 90.0)
	var a100 := deg_to_rad(_angle(100) - 90.0)
	var a120 := deg_to_rad(_angle(MAX_KMH) - 90.0)
	draw_arc(c, 84, a0, a70, 48, Color("3ec7ff"), 9, true)
	draw_circle(_polar(c, 84, _angle(0)), 4.5, Color("3ec7ff"))
	draw_arc(c, 84, a70, a100, 24, Color("ffd84d"), 9, true)
	draw_arc(c, 84, a100, a120, 20, Color("ff5d5d"), 9, true)
	draw_circle(_polar(c, 84, _angle(MAX_KMH)), 4.5, Color("ff5d5d"))
	# ticks + labels
	var f := HudTheme.font()
	var v := 0.0
	while v <= MAX_KMH + 0.1:
		var major := int(v) % 20 == 0
		var a := _angle(v)
		var p0 := _polar(c, 66.0 if major else 70.0, a)
		var p1 := _polar(c, 78.0, a)
		draw_line(p0, p1, Color.WHITE if major else Color(1, 1, 1, 0.55), 3.5 if major else 2.0, true)
		if major:
			var lp := _polar(c, 53.0, a)
			var txt := str(int(v))
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			f.draw_string(get_canvas_item(), lp + Vector2(-w * 0.5, 4.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		v += 10.0
	var unit := "km/h"
	var uw := f.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	f.draw_string(get_canvas_item(), Vector2(100 - uw * 0.5, 172), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
	# needle
	var ang := deg_to_rad(_angle(value))
	var needle := PackedVector2Array()
	for q in [Vector2(-5, 6), Vector2(-1.2, -78), Vector2(1.2, -78), Vector2(5, 6)]:
		needle.append(c + q.rotated(ang))
	var outline := needle.duplicate()
	outline.append(needle[0])
	draw_polyline(outline, INK, 3.0, true)
	draw_colored_polygon(needle, Color("ff5d5d"))
	draw_circle(c, 11, INK)
	draw_circle(c, 6, Color("ffd84d"))
	# digit
	var digit := str(int(round(value)))
	HudTheme.draw_text(self, Vector2(100, 142), digit, 34.0, Color("ffd84d"), INK, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
