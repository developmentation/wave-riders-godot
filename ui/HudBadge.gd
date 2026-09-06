class_name HudBadge
extends Control
## Race readout badge (.wr-badge): navy gradient pill-ish box with an orange tile holding an
## icon and a row of text segments, e.g. "LAP" + big yellow "1" + small "/3".

const INK := Color("05324f")

## Font size in px; the whole badge scales with it (1em = fs).
var fs := 32.0:
	set(v):
		fs = v
		update_minimum_size()
		queue_redraw()
## Tile content: a HudIcon name or "txt:🤿".
var tile_icon := "flag":
	set(v):
		tile_icon = v
		queue_redraw()
## Segments: [{text, scale, color}] drawn inline.
var segments: Array = []:
	set(v):
		segments = v
		update_minimum_size()
		queue_redraw()
## Minimum width of the value area in em (timer keeps a fixed width).
var min_value_em := 0.0:
	set(v):
		min_value_em = v
		update_minimum_size()
var align_right := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_text(parts: Array) -> void:
	# parts: alternating plain strings and dictionaries; convenience for update()
	segments = parts


func _value_width() -> float:
	var w := 0.0
	for s in segments:
		var sc: float = s.get("scale", 1.0)
		w += HudTheme.text_width(str(s.get("text", "")), fs * 1.05 * sc)
	return maxf(w, min_value_em * fs)


func _get_minimum_size() -> Vector2:
	var h := fs * (1.35 + 0.36 + 0.22)
	var w := fs * (0.22 + 1.35 + 0.35 + 0.55 + 0.22) + _value_width()
	return Vector2(w, h + fs * 0.18)


func _draw() -> void:
	var drop := fs * 0.18
	var body := Rect2(Vector2.ZERO, Vector2(size.x, size.y - drop))
	var rad := fs * 0.55
	HudPanel.draw_panel(self, body, rad, [Color(14.0 / 255, 70.0 / 255, 122.0 / 255, 0.88), Color(4.0 / 255, 30.0 / 255, 56.0 / 255, 0.92)],
		fs * 0.11, Color.WHITE, drop, Color(0, 0, 0, 0.35), fs * 0.6, 0.3, 0.35)
	# tile
	var tsz := fs * 1.35
	var tile := Rect2(Vector2(fs * 0.22 + fs * 0.11, (body.size.y - tsz) * 0.5), Vector2(tsz, tsz))
	HudPanel.draw_gradient_poly(self, HudPanel.rrect_points(tile, fs * 0.38), [Color("ffe36b"), Color("ff9f1a")], tile.position.y, tile.end.y)
	var inner := tile.grow(-fs * 0.22)
	if tile_icon.begins_with("txt:"):
		HudTheme.draw_text(self, Vector2(tile.get_center().x, HudTheme.baseline(tile.get_center().y, inner.size.y * 0.9)), tile_icon.substr(4), inner.size.y * 0.9, INK, INK, 0.0, HORIZONTAL_ALIGNMENT_CENTER, -1, false)
	else:
		HudIcon.paint(self, tile_icon, inner, INK, Color("ffe36b"))
	# value segments
	var x := tile.end.x + fs * 0.35
	var avail := body.end.x - fs * 0.55 - fs * 0.11 - x
	var vw := _value_width()
	if align_right:
		x += maxf(0.0, avail - vw)
	var cy := body.size.y * 0.5
	for s in segments:
		var sc: float = s.get("scale", 1.0)
		var col: Color = s.get("color", Color.WHITE)
		var t := str(s.get("text", ""))
		var size_px := fs * 1.05 * sc
		HudTheme.draw_text(self, Vector2(x, HudTheme.baseline(cy, size_px)), t, size_px, col, INK, size_px * 0.075, HORIZONTAL_ALIGNMENT_LEFT)
		x += HudTheme.text_width(t, size_px)
