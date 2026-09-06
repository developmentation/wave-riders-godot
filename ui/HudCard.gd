class_name HudCard
extends Control
## Garage boat card (.wr-boat): emoji, name, description and three stat bars on a blue
## gradient card; the selected card grows, gets a yellow border + glow and a bobbing icon.

signal picked(id: String)

const INK := Color("05324f")
const STAT_KEYS := ["speed", "turning", "steady"]
const STAT_ICONS := ["🚀", "↩️", "⚖️"]

var boat: Dictionary = {}
var selected := false:
	set(v):
		if selected != v:
			selected = v
			_apply_selected()
var accent := Color("ff9f1a")
var k := 1.0  # css px → canvas px
var short := false

var _icon: Label
var _name: Label
var _desc: Label
var _stat_labels: Array[Label] = []
var _stat_icons: Array[Label] = []
var _t := 0.0
var _press := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon = HudTheme.make_label("🚤", 60, Color.WHITE, false)
	_name = HudTheme.make_label("Boat", 26)
	_desc = HudTheme.make_label("", 14, HudTheme.PALE, false)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_icon)
	add_child(_name)
	add_child(_desc)
	for i in 3:
		var ic := HudTheme.make_label(STAT_ICONS[i], 13, Color.WHITE, false)
		var lb := HudTheme.make_label(STAT_KEYS[i].capitalize(), 13, Color("dff4ff"), false, HORIZONTAL_ALIGNMENT_LEFT)
		add_child(ic)
		add_child(lb)
		_stat_icons.append(ic)
		_stat_labels.append(lb)


func setup(b: Dictionary, sel: bool) -> void:
	boat = b
	_icon.text = str(b.get("icon", "🚤"))
	_name.text = str(b.get("label", b.get("id", "")))
	_desc.text = str(b.get("description", ""))
	var cols: Array = b.get("colors", [])
	accent = HudTheme.to_color(cols[0]) if cols.size() > 0 else Color("ff9f1a")
	selected = sel
	queue_redraw()


## Lay the card out for the given css→canvas factor and viewport (css units).
func layout(k_: float, css_vmin: float, short_: bool) -> void:
	k = k_
	short = short_
	var vm := css_vmin / 100.0
	var icon_fs := (clampf(9.0 * vm, 44, 80) if short else clampf(11.0 * vm, 56, 120)) * k
	var name_fs := (clampf(3.4 * vm, 19, 40) if short else clampf(3.8 * vm, 22, 40)) * k
	var desc_fs := clampf(2.0 * vm, 13, 20) * k
	var stat_fs := (12.0 if short else clampf(1.9 * vm, 12, 19)) * k
	var pad_y := clampf(2.0 * vm, 10, 22) * k
	var pad_x := clampf(1.8 * vm, 10, 20) * k
	var gap := clampf(0.8 * vm, 2, 10) * k
	var w := size.x
	HudTheme.style_label(_icon, icon_fs, Color.WHITE, false)
	HudTheme.style_label(_name, name_fs)
	HudTheme.style_label(_desc, desc_fs, HudTheme.PALE, false)
	var y := pad_y
	_icon.position = Vector2(0, y)
	_icon.size = Vector2(w, icon_fs * 1.05)
	y += icon_fs * 1.05 + gap
	_name.position = Vector2(pad_x * 0.5, y)
	_name.size = Vector2(w - pad_x, name_fs * 1.1)
	y += name_fs * 1.1 + gap
	_desc.position = Vector2(pad_x, y)
	var desc_h := HudTheme.font().get_multiline_string_size(_desc.text, HORIZONTAL_ALIGNMENT_CENTER, w - pad_x * 2, int(round(desc_fs))).y
	desc_h = clampf(desc_h, desc_fs * 1.2, desc_fs * 1.25 * 3)
	_desc.size = Vector2(w - pad_x * 2, desc_h)
	y += desc_h + gap + clampf(1.0 * vm, 4, 12) * k
	var row_gap := clampf(0.6 * vm, 3, 8) * k
	for i in 3:
		HudTheme.style_label(_stat_icons[i], stat_fs, Color.WHITE, false)
		HudTheme.style_label(_stat_labels[i], stat_fs, Color("dff4ff"), false)
		_stat_icons[i].position = Vector2(pad_x, y)
		_stat_icons[i].size = Vector2(stat_fs * 1.4, stat_fs * 1.2)
		_stat_labels[i].position = Vector2(pad_x + stat_fs * 1.75, y)
		_stat_labels[i].size = Vector2(stat_fs * 4.2, stat_fs * 1.2)
		y += stat_fs * 1.2 + row_gap
	y += pad_y - row_gap
	custom_minimum_size = Vector2(w, y)
	size.y = y
	pivot_offset = size * 0.5
	_apply_selected()
	queue_redraw()


func _apply_selected() -> void:
	scale = Vector2.ONE * (1.06 if selected else 1.0)
	queue_redraw()


func _process(dt: float) -> void:
	if selected and is_visible_in_tree():
		_t += dt
		_icon.pivot_offset = _icon.size * 0.5
		_icon.rotation = deg_to_rad(sin(_t * TAU / 2.0) * 1.0)
		_icon.scale = Vector2.ONE * (1.0 + 0.02 * sin(_t * TAU / 2.0))


func _draw() -> void:
	var drop := 6.0 * k
	var body := Rect2(Vector2.ZERO, Vector2(size.x, size.y - drop))
	var rad := clampf(size.x * 0.13, 18.0 * k, 34.0 * k)
	var border := clampf(size.x * 0.03, 4.0 * k, 7.0 * k)
	if selected:
		draw_colored_polygon(HudPanel.rrect_points(body.grow(border), rad + border), Color(1, 0.847, 0.302, 0.35))
	var stops := [Color(20.0 / 255, 100.0 / 255, 168.0 / 255, 0.85), Color(6.0 / 255, 46.0 / 255, 86.0 / 255, 0.92)]
	if selected:
		stops = [Color(30.0 / 255, 130.0 / 255, 210.0 / 255, 0.92), Color(8.0 / 255, 60.0 / 255, 110.0 / 255, 0.95)]
	HudPanel.draw_panel(self, body, rad, stops, border, HudTheme.YELLOW if selected else Color(1, 1, 1, 0.6),
		drop, Color(0, 0, 0, 0.3), 16.0 * k, 0.35, 0.0)
	# stat bars
	var stats: Dictionary = boat.get("stats", {})
	for i in 3:
		var lb := _stat_labels[i]
		var bar_h := lb.size.y * 0.75
		var x0 := lb.position.x + lb.size.x + lb.size.y * 0.35
		var x1 := size.x - _stat_icons[i].position.x
		var r := Rect2(x0, lb.position.y + (lb.size.y - bar_h) * 0.5, x1 - x0, bar_h)
		if r.size.x < 4:
			continue
		draw_colored_polygon(HudPanel.rrect_points(r, bar_h * 0.5, 4), Color(0, 0, 0, 0.4))
		var v := clampf(float(stats.get(STAT_KEYS[i], 0.5)), 0.08, 1.0)
		var fill := Rect2(r.position, Vector2(r.size.x * v, r.size.y))
		var pts := HudPanel.rrect_points(fill, bar_h * 0.5, 4)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		var g0 := Color("46e07a")
		var g1 := Color("ffd84d")
		var g2 := Color("ff9f1a")
		for j in pts.size():
			var t := clampf((pts[j].x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
			cols[j] = g0.lerp(g1, t / 0.7) if t < 0.7 else g1.lerp(g2, (t - 0.7) / 0.3)
		draw_polygon(pts, cols)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = true
			accept_event()
		elif _press:
			_press = false
			accept_event()
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				picked.emit(str(boat.get("id", "")))
