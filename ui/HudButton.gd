class_name HudButton
extends Control
## Big candy button of the web HUD (.wr-big / .wr-sysbtn / .wr-arrowbtn / .wr-round / .wr-pedal /
## .wr-cycle / .wr-swatch). Draws its own pill/circle with gradient, white border, hard drop
## shadow and press animation; content is an icon (HudIcon name or "txt:…" for emoji) + text.

signal pressed

const INK := Color("05324f")

## Gradient stops (top→bottom), hard-drop colour, text colour, icon colour.
const STYLES := {
	"yellow": {"stops": ["ffe66e", "ffd84d", "ffb42e"], "drop": "b86e00", "text": "05324f", "icon": "05324f"},
	"green": {"stops": ["7dffab", "46e07a", "22b85a"], "drop": "137a3b", "text": "05324f", "icon": "05324f"},
	"blue": {"stops": ["5fd0ff", "1d9be0", "0a7fbf"], "drop": "04486e", "text": "ffffff", "icon": "ffffff"},
	"red": {"stops": ["ff7a7a", "e03434"], "drop": "7a1010", "text": "ffffff", "icon": "ffffff"},
	"sys": {"stops": [Color(20.0 / 255, 90.0 / 255, 150.0 / 255, 0.9), Color(5.0 / 255, 40.0 / 255, 76.0 / 255, 0.94)], "drop": Color(0, 0, 0, 0.35), "text": "ffffff", "icon": "ffffff"},
	"home": {"stops": [Color(20.0 / 255, 90.0 / 255, 150.0 / 255, 0.9), Color(5.0 / 255, 40.0 / 255, 76.0 / 255, 0.94)], "drop": Color(0, 0, 0, 0.35), "text": "ffd84d", "icon": "ffd84d"},
	"sys_on": {"stops": ["1d9be0", "0a5c8d"], "drop": Color(0, 0, 0, 0.35), "text": "ffd84d", "icon": "ffd84d"},
	"horn": {"stops": ["5fd0ff", "1d9be0", "0a7fbf"], "drop": Color(0, 0, 0, 0.35), "text": "ffffff", "icon": "ffffff"},
	"boost": {"stops": ["b48cff", "7a4de0", "5a2fc0"], "drop": Color(0, 0, 0, 0.35), "text": "ffd84d", "icon": "ffd84d"},
	"boost_down": {"stops": ["ffd84d", "ff9f1a"], "drop": Color(0, 0, 0, 0.35), "text": "ffffff", "icon": "ffffff"},
	"go": {"stops": ["7dffab", "46e07a", "22b85a"], "drop": Color(0, 0, 0, 0.4), "text": "ffffff", "icon": "ffffff"},
	"stop": {"stops": ["ff9a9a", "ff5d5d", "d83030"], "drop": Color(0, 0, 0, 0.4), "text": "ffffff", "icon": "ffffff"},
	"dive": {"stops": ["7fe8ff", "1fb6e6", "0a7fbf"], "drop": "04486e", "text": "05324f", "icon": "05324f"},
	"arrow": {"stops": ["ffe66e", "ffd84d", "ffb42e"], "drop": "b86e00", "text": "05324f", "icon": "05324f"},
	"arrow_down": {"stops": ["fff2a0", "ffe066"], "drop": "b86e00", "text": "05324f", "icon": "05324f"},
	"cycle": {"stops": ["ffe66e", "ffb42e"], "drop": "b86e00", "text": "05324f", "icon": "05324f"},
	"swatch": {"stops": ["ffffff"], "drop": Color(0, 0, 0, 0.35), "text": "ffffff", "icon": "ffffff"},
}

@export var text := "":
	set(v):
		text = v
		update_minimum_size()
		queue_redraw()
@export var icon := "":
	set(v):
		icon = v
		update_minimum_size()
		queue_redraw()
@export var style := "yellow":
	set(v):
		style = v
		queue_redraw()
@export var shape := "pill":  # pill | circle | rrect | pedal
	set(v):
		shape = v
		queue_redraw()
@export var font_size := 32.0:
	set(v):
		font_size = v
		update_minimum_size()
		queue_redraw()
@export var min_height := 0.0:
	set(v):
		min_height = v
		update_minimum_size()
@export var align_start := false
@export var swatch_color := Color.WHITE:
	set(v):
		swatch_color = v
		queue_redraw()
@export var corner := 0.0  # rrect radius (0 = auto)
@export var pad_x := 1.1   # horizontal padding in em (pill)

var is_down := false:
	set(v):
		if is_down != v:
			is_down = v
			queue_redraw()
var toggled := false:
	set(v):
		toggled = v
		queue_redraw()
var off := false:
	set(v):
		off = v
		queue_redraw()
var _press_inside := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _get_minimum_size() -> Vector2:
	if shape != "pill":
		return Vector2.ZERO
	var fs := font_size
	var w := HudTheme.text_width(text, fs) if text != "" else 0.0
	if icon != "":
		w += fs * 0.9 + (fs * 0.35 if text != "" else 0.0)
	w += fs * pad_x * 2.0
	var h := maxf(min_height, fs * 1.5 + drop_px())
	return Vector2(w, h)


func drop_px() -> float:
	match shape:
		"pill":
			return maxf(3.0, font_size * 0.2)
		"pedal":
			return maxf(4.0, size.y * 0.06)
		_:
			return maxf(3.0, minf(size.x, size.y) * 0.075)


func _style() -> Dictionary:
	var key := style
	if is_down and style == "boost":
		key = "boost_down"
	elif is_down and style == "arrow":
		key = "arrow_down"
	elif toggled and style == "sys":
		key = "sys_on"
	return STYLES.get(key, STYLES["yellow"])


func _draw() -> void:
	var st := _style()
	var drop := drop_px()
	var dy := drop * 0.7 if is_down else 0.0
	var body := Rect2(Vector2(0, dy), Vector2(size.x, size.y - drop))
	var rad := 0.0
	match shape:
		"pill", "circle":
			rad = minf(body.size.x, body.size.y) * 0.5
		"pedal":
			rad = clampf(minf(body.size.x, body.size.y) * 0.22, 14.0, 34.0)
		_:
			rad = corner if corner > 0.0 else clampf(minf(body.size.x, body.size.y) * 0.28, 12.0, 30.0)
	var stops: Array = []
	if style == "swatch":
		stops = [swatch_color.lightened(0.18), swatch_color, swatch_color.darkened(0.18)]
	else:
		for c in st["stops"]:
			stops.append(HudTheme.to_color(c))
	var drop_col: Color = HudTheme.to_color(st["drop"])
	var border_w := clampf(minf(body.size.x, body.size.y) * 0.06, 3.0, 8.0)
	if shape == "pill":
		border_w = clampf(font_size * 0.12, 3.0, 8.0)
	var border_col := Color.WHITE
	if style == "swatch":
		border_col = Color(1, 1, 1, 0.7) if not toggled else Color.WHITE
		if toggled:
			draw_colored_polygon(HudPanel.rrect_points(body.grow(4.0), rad + 4.0), HudTheme.YELLOW)
	var soft := 0.0 if is_down else clampf(drop * 2.2, 6.0, 26.0)
	HudPanel.draw_panel(self, body, rad, stops, border_w, border_col, 0.0 if is_down else drop, drop_col, soft, 0.35, 0.55)
	if style == "swatch":
		return
	# ---- content
	var icon_col: Color = HudTheme.to_color(st["icon"])
	var text_col: Color = HudTheme.to_color(st["text"])
	if off:
		icon_col = HudTheme.RED
	var c := body.get_center()
	match shape:
		"circle":
			var isz := minf(body.size.x, body.size.y) * (0.6 if style == "sys" or style == "sys_on" else 0.58)
			if icon.begins_with("txt:"):
				HudTheme.draw_text(self, Vector2(c.x, HudTheme.baseline(c.y, isz * 0.8)), icon.substr(4), isz * 0.8, icon_col, INK, 0.0)
			elif icon != "":
				HudIcon.paint(self, icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), icon_col, INK)
			if text != "":
				HudTheme.draw_text(self, Vector2(c.x, HudTheme.baseline(c.y, font_size)), text, font_size, text_col, INK, 0.0)
		"rrect":
			var isz := minf(body.size.x, body.size.y) * 0.68
			if icon != "":
				HudIcon.paint(self, icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), icon_col, INK)
		"pedal":
			var lab_fs := font_size
			var pad := body.size.y * 0.07
			var lab_h := lab_fs * 1.15
			var ir := Rect2(body.position.x + body.size.x * 0.15, body.position.y + pad, body.size.x * 0.7, body.size.y - pad * 2.0 - lab_h)
			HudIcon.paint(self, "pedal", ir, Color.WHITE, INK)
			var pos := Vector2(c.x, HudTheme.baseline(body.end.y - pad - lab_h * 0.5, lab_fs))
			HudTheme.draw_text(self, pos, text, lab_fs, Color.WHITE, Color(0, 0, 0, 0.45), lab_fs * 0.06, HORIZONTAL_ALIGNMENT_CENTER, -1, true)
		_:
			var fs := font_size
			var tw := HudTheme.text_width(text, fs) if text != "" else 0.0
			var isz := fs * 0.9 if icon != "" else 0.0
			var gap := fs * 0.35 if (icon != "" and text != "") else 0.0
			var total := tw + isz + gap
			var x := c.x - total * 0.5
			if align_start:
				x = body.position.x + fs * 0.9
			if icon != "":
				if icon.begins_with("txt:"):
					HudTheme.draw_text(self, Vector2(x + isz * 0.5, HudTheme.baseline(c.y, fs * 0.85)), icon.substr(4), fs * 0.85, icon_col, INK, 0.0, HORIZONTAL_ALIGNMENT_CENTER, -1, false)
				else:
					HudIcon.paint(self, icon, Rect2(Vector2(x, c.y - isz * 0.5), Vector2(isz, isz)), icon_col, INK)
				x += isz + gap
			if text != "":
				var shadow_col := Color(1, 1, 1, 0.5) if text_col == INK else Color(0, 0, 0, 0.35)
				var f := HudTheme.font()
				var px := int(round(fs))
				var bl := HudTheme.baseline(c.y, fs)
				f.draw_string(get_canvas_item(), Vector2(x, bl + fs * 0.05), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, shadow_col)
				f.draw_string(get_canvas_item(), Vector2(x, bl), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, text_col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_inside = true
			is_down = true
			accept_event()
		elif _press_inside:
			_press_inside = false
			is_down = false
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_inside = true
			is_down = true
			accept_event()
		elif _press_inside:
			_press_inside = false
			is_down = false
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _press_inside:
		is_down = false
