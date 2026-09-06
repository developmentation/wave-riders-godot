class_name StubHud
extends CanvasLayer
## Text-only stand-in for ui/Hud.tscn so screenshots show the game state (screen, speed, lap,
## position, time, countdown) before the real HUD lands. Same calls Main.gd makes: show_screen(),
## update(frame), toast(text). Emits none of the HUD signals (keyboard drives the flow instead).

var _label: Label
var _big: Label
var _toast: Label
var _toast_t := 0.0
var _screen := "boot"
var _data: Dictionary = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_big = Label.new()
	_big.anchors_preset = Control.PRESET_CENTER
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.grow_vertical = Control.GROW_DIRECTION_BOTH
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_font_size_override("font_size", 96)
	_big.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_big.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2, 0.9))
	_big.add_theme_constant_override("outline_size", 12)
	add_child(_big)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 90
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_theme_color_override("font_outline_color", Color(0.7, 0.1, 0.1, 0.9))
	_toast.add_theme_constant_override("outline_size", 8)
	add_child(_toast)


func show_screen(screen: String, data: Dictionary = {}) -> void:
	_screen = screen
	_data = data
	match screen:
		"title":
			_big.text = "WAVE RIDERS\n[Enter] start"
		"garage":
			_big.text = "GARAGE\n[Enter] go"
		"paused":
			_big.text = "PAUSED"
		"results":
			_big.text = "PLACE %d\n%s  %.1f s" % [int(data.get("place", 0)), "*".repeat(int(data.get("stars", 0))), float(data.get("time", 0.0))]
		_:
			_big.text = ""


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.5


func update(f: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("%s / %s   %d km/h" % [String(f.get("state", "")), String(f.get("world", "")), int(round(float(f.get("speed_kmh", 0.0))))])
	if int(f.get("laps", 0)) > 0:
		lines.append("LAP %d/%d   P%d/%d   %05.1f s" % [int(f.get("lap", 0)), int(f.get("laps", 0)), int(f.get("position", 0)), int(f.get("racers", 0)), float(f.get("time", 0.0))])
		var dir := float(f.get("next_gate_dir", 0.0))
		lines.append("next gate %s %d deg" % ["right" if dir > 0 else "left", int(round(abs(rad_to_deg(dir))))])
	if bool(f.get("submerged", false)):
		lines.append("depth %.1f m" % float(f.get("depth", 0.0)))
	_label.text = "\n".join(lines)
	var cd := float(f.get("countdown", 0.0))
	if _screen == "race" and cd > 0.0:
		_big.text = str(ceili(cd))
	elif _screen == "race" and _big.text != "" and _big.text != "GO!" and cd <= 0.0 and float(f.get("time", 0.0)) < 1.0:
		_big.text = "GO!"
	elif _screen == "race" and float(f.get("time", 0.0)) >= 1.0 and _big.text == "GO!":
		_big.text = ""
	if _toast_t > 0.0:
		_toast_t -= 1.0 / 60.0
		if _toast_t <= 0.0:
			_toast.text = ""
