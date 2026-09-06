class_name Hud
extends CanvasLayer
## Wave Riders HUD — port of src/game/Hud.js + game.css. Every screen the player sees over the
## ocean plus the touch controls that drive the boat.
##
##   var hud := preload("res://ui/Hud.tscn").instantiate()
##   hud.set_boats(list)                        # optional garage catalogue
##   hud.show_screen("title" | "garage" | "hub" | "race" | "results" | "paused", data)
##   hud.update(frame)                          # every frame; cheap, only redraws on change
##
## frame = { speed_kmh, lap, laps, position, racers, time, countdown, next_gate_dir (rad, +right),
##           next_gate_pitch (rad, +up), submerged, depth, state, world, stars, best_time }
## Touch controls write Controls.virtual = {steer, throttle, brake, boost, dive, active} every
## frame while the race/hub screens are up (duck-typed: only if a /root/Controls node exists).
## NOTE: CanvasLayer already owns a native `show()`, which GDScript cannot overload, hence
## `show_screen()`.

signal start(info: Dictionary)          # {from: "title"|"garage", boat: String, color: int}
signal select_boat(id: String, color: int)
signal pause
signal resume
signal camera
signal reset
signal mute(muted: bool)
signal exit
signal horn
signal race_again
signal garage
signal matte
signal fullscreen
signal quit
signal tilt(enabled: bool)

const SCREENS := ["title", "garage", "hub", "race", "results", "paused"]
const PLAY_SCREENS := ["race", "hub"]
const SPEEDO_MAX := 120.0
const WHEEL_MAX_DEG := 100.0
const INK := Color("05324f")

const DEFAULT_BOATS := [
	{"id": "jetski", "label": "Jet Ski", "icon": "🏄", "description": "Zippy and bouncy — jump the waves!", "colors": ["#ffc236", "#ff7a3d", "#49c687", "#9d6cf0"], "stats": {"speed": 0.8, "turning": 1.0, "steady": 0.3}},
	{"id": "speedboat", "label": "Speedboat", "icon": "🚤", "description": "The fastest boat on the water!", "colors": ["#d84c48", "#5a8fdd", "#49c687", "#ffc236", "#ff7a3d", "#9d6cf0"], "stats": {"speed": 1.0, "turning": 0.6, "steady": 0.55}},
	{"id": "sailboat", "label": "Sailboat", "icon": "⛵", "description": "Catch the wind and glide!", "colors": ["#f4f4f4", "#d84c48"], "stats": {"speed": 0.45, "turning": 0.4, "steady": 0.7}},
	{"id": "pontoon", "label": "Pontoon", "icon": "🛥️", "description": "Slow and steady party boat — toot the horn!", "colors": ["#5a8fdd", "#d84c48", "#49c687", "#9d6cf0"], "stats": {"speed": 0.35, "turning": 0.35, "steady": 1.0}},
	{"id": "fishing", "label": "Fishing Boat", "icon": "🎣", "description": "Steady as a rock — toot the foghorn!", "colors": ["#5a8fdd", "#d84c48", "#49c687", "#ffc236"], "stats": {"speed": 0.4, "turning": 0.45, "steady": 0.9}},
	{"id": "tug", "label": "Tugboat", "icon": "🚢", "description": "Big and strong — bumps through anything!", "colors": ["#d84c48", "#49c687", "#ffc236"], "stats": {"speed": 0.3, "turning": 0.4, "steady": 1.0}},
	{"id": "airboat", "label": "Airboat", "icon": "🌀", "description": "Whoosh! Super fast and super slidey!", "colors": ["#49c687", "#ff7a3d", "#9d6cf0", "#a9d9fb"], "stats": {"speed": 0.85, "turning": 0.75, "steady": 0.35}},
	{"id": "towboat", "label": "Tow Boat", "icon": "⛴️", "description": "Twin smokestacks and a huge engine!", "colors": ["#9d6cf0", "#ff7a3d"], "stats": {"speed": 0.95, "turning": 0.55, "steady": 0.6}},
	{"id": "rowboat", "label": "Rowboat", "icon": "🚣", "description": "Row, row, row your boat — silly slow!", "colors": ["#d84c48", "#ffc236", "#49c687", "#9d6cf0"], "stats": {"speed": 0.15, "turning": 0.9, "steady": 0.5}},
]
# Same left-to-right order as the portal arc in the harbour.
const WORLD_ICONS := [
	{"id": "storm", "icon": "⛈️", "label": "Storm Run"},
	{"id": "swell", "icon": "🌊", "label": "Rolling Swell"},
	{"id": "lagoon", "icon": "☀️", "label": "Sunny Lagoon"},
	{"id": "giant", "icon": "🏔️", "label": "Titan Swell"},
	{"id": "tempest", "icon": "🌩️", "label": "The Perfect Storm"},
	{"id": "deep", "icon": "🤿", "label": "The Deep Run"},
]
const CONFETTI_COLORS := ["ffd84d", "ff9f1a", "46e07a", "3ec7ff", "ff5d5d", "ff8fd0", "ffffff"]

# ---- public state
var screen := ""
var touch := false
var muted := false
var tilt_on := false
var matte_on := false
var boats: Array = []
var selected_boat := "speedboat"
var color_index := 0
var stars: Dictionary = {}
var last: Dictionary = {}
var virtual := {"steer": 0.0, "throttle": 0.0, "brake": 0.0, "boost": false, "dive": 0.0, "active": false}

# ---- internals
var _root: Control
var _scr: Dictionary = {}          # screen name -> Control
var _m: Dictionary = {}            # current metrics
var _c: Dictionary = {}            # per-frame cache
var _t := 0.0
var _real_touch := false
var _controls: Node = null
var _controls_check := 0
var _hint_shown := false
var _hint_t := -1.0
var _wrong_t := 0.0
var _sub := false
var _compact := false
var _fingers: Dictionary = {}      # finger index -> ctl name
var _held := {"left": false, "right": false, "throttle": false, "brake": false, "boost": false, "horn": false, "up": false, "down": false}
var _wheel_angle := 0.0
var _wheel_drag := false
var _wheel_last_a := 0.0
var _wheel_c := Vector2.ZERO
var _count_t := -1.0
var _count_go := false
var _toasts: Array = []
var _star_t := -1.0
var _card_t := -1.0
var _pause_t := -1.0
var _confetti: Array = []
var _results_stars_n := 0
var _mute_btns: Array = []
var _touch_ctls: Dictionary = {}
var _layout_dirty := true

# title
var _title_logo: Control
var _title_logo_wrap: Control
var _title_boats_row: HBoxContainer
var _title_boats: Array = []
var _title_play: HudButton
var _title_tap: Label
var _title_box: VBoxContainer
var _title_corner: HBoxContainer
# garage
var _garage_box: VBoxContainer
var _garage_h: Label
var _garage_row: HBoxContainer
var _garage_prev: HudButton
var _garage_next: HudButton
var _garage_scroll: ScrollContainer
var _garage_cards: HBoxContainer
var _garage_foot: HBoxContainer
var _garage_swatches: HBoxContainer
var _garage_go: HudButton
var _cards: Array = []
# hub
var _hub_panel: HudPanel
var _hub_margin: MarginContainer
var _hub_box: VBoxContainer
var _hub_text: Label
var _hub_worlds: HBoxContainer
var _hub_world_nodes: Array = []
# race
var _pos_badge: HudBadge
var _lap_badge: HudBadge
var _timer_badge: HudBadge
var _gate: HudIcon
var _wrong: HudPanel
var _wrong_label: Label
var _speedo: HudSpeedo
var _depth: HudBadge
var _count: Label
var _pitch: Label
# results
var _results_confetti: Control
var _results_card: HudPanel
var _results_margin: MarginContainer
var _results_box: VBoxContainer
var _results_title: HBoxContainer
var _results_t1: Label
var _results_place: Label
var _results_t2: Label
var _results_stars: HBoxContainer
var _star_icons: Array = []
var _results_times: HBoxContainer
var _results_time: Label
var _results_best: Label
var _results_lbls: Array = []
var _results_btns: HBoxContainer
var _results_again: HudButton
var _results_exit: HudButton
# paused
var _pause_card: HudPanel
var _pause_margin: MarginContainer
var _pause_box: VBoxContainer
var _pause_h: Label
var _pause_btns: Array = []
var _pause_row: HBoxContainer
var _pause_sys: Dictionary = {}
# always-on
var _sys: HBoxContainer
var _sys_btns: Dictionary = {}
var _touch: Control
var _wheel: HudIcon
var _keys_panel: HudPanel
var _keys: RichTextLabel
var _toast_box: Control
var _rotate: Control
var _rotate_label: Label
var _rotate_icon: Label


# ======================================================================== lifecycle
func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_real_touch = DisplayServer.is_touchscreen_available()
	var args := OS.get_cmdline_user_args()
	touch = _real_touch or args.has("--touch") or OS.get_environment("WR_TOUCH") == "1"
	if boats.is_empty():
		boats = DEFAULT_BOATS.duplicate(true)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudTheme.theme()
	add_child(_root)
	_build()
	_root.resized.connect(_on_resized)
	add_to_group("harness_state")
	_layout()
	_render_cards()
	_render_world_stars()
	_set_screen_visibility()


func _on_resized() -> void:
	_layout_dirty = true


func get_harness_state() -> Dictionary:
	return {"hud": screen, "touch": touch, "compact": _compact, "sub": _sub, "virtual": virtual.duplicate()}


# ============================================================================ build
func _ctl(parent: Node, n: String, full := true) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if full:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	return c


func _dim(parent: Control, inner: Color, outer: Color, cy := 0.6) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, cy)
	tex.fill_to = Vector2(1.05, cy)
	tex.width = 64
	tex.height = 64
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(tr)
	return tr


func _hbox(parent: Node, n: String) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.name = n
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


func _vbox(parent: Node, n: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.name = n
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


func _btn(parent: Node, n: String, style: String, shape: String, icon := "", text := "", act := "") -> HudButton:
	var b := HudButton.new()
	b.name = n
	b.style = style
	b.shape = shape
	b.icon = icon
	b.text = text
	if act != "":
		b.pressed.connect(_act.bind(act))
	parent.add_child(b)
	if act == "mute":
		_mute_btns.append(b)
	return b


func _screen(n: String) -> Control:
	var s := _ctl(_root, n)
	s.visible = false
	_scr[n] = s
	return s


func _build() -> void:
	# ------------------------------------------------------------------ title
	var title := _screen("title")
	var tdim := _dim(title, Color(4.0 / 255, 50.0 / 255, 90.0 / 255, 0.35), Color(2.0 / 255, 20.0 / 255, 42.0 / 255, 0.7), 0.7)
	tdim.gui_input.connect(_on_title_input)
	_title_box = _vbox(title, "Box")
	_title_logo_wrap = _ctl(_title_box, "LogoWrap", false)
	_title_logo = HudLogo.new()
	_title_logo.name = "Logo"
	_title_logo_wrap.add_child(_title_logo)
	_title_boats_row = _hbox(_title_box, "Boats")
	for e in ["🚤", "⛵", "🏄"]:
		var wrap := _ctl(_title_boats_row, "Wrap", false)
		var l := HudTheme.make_label(e, 40, Color.WHITE, false)
		wrap.add_child(l)
		_title_boats.append(l)
	_title_play = _btn(_title_box, "Play", "yellow", "pill", "play", "PLAY", "play")
	_title_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_tap = HudTheme.make_label("tap anywhere to start", 20, Color(1, 1, 1, 0.85), false)
	_title_box.add_child(_title_tap)
	_title_corner = _hbox(title, "Corner")
	_btn(_title_corner, "Mute", "sys", "circle", "sound", "", "mute")
	_btn(_title_corner, "Full", "sys", "circle", "full", "", "fullscreen")
	var tq := _btn(_title_corner, "Quit", "sys", "circle", "txt:✖", "", "quit")
	tq.style = "red"

	# ----------------------------------------------------------------- garage
	var gar := _screen("garage")
	_dim(gar, Color(4.0 / 255, 50.0 / 255, 90.0 / 255, 0.3), Color(2.0 / 255, 20.0 / 255, 42.0 / 255, 0.72), 0.6)
	_garage_box = _vbox(gar, "Box")
	_garage_h = HudTheme.make_label("Choose your boat", 40)
	_garage_box.add_child(_garage_h)
	_garage_row = _hbox(_garage_box, "Row")
	_garage_prev = _btn(_garage_row, "Prev", "cycle", "circle", "left", "", "prevBoat")
	_garage_prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_garage_scroll = ScrollContainer.new()
	_garage_scroll.name = "Scroll"
	_garage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_garage_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_garage_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_garage_row.add_child(_garage_scroll)
	_garage_cards = _hbox(_garage_scroll, "Cards")
	_garage_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_garage_next = _btn(_garage_row, "Next", "cycle", "circle", "right", "", "nextBoat")
	_garage_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_garage_foot = _hbox(_garage_box, "Foot")
	_garage_swatches = _hbox(_garage_foot, "Swatches")
	_garage_go = _btn(_garage_foot, "Go", "green", "pill", "", "GO!", "go")

	# -------------------------------------------------------------------- hub
	var hub := _screen("hub")
	_hub_panel = HudPanel.new()
	_hub_panel.name = "Hint"
	_hub_panel.stops = [HudTheme.NAVY, HudTheme.NAVY]
	_hub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hub.add_child(_hub_panel)
	_hub_margin = MarginContainer.new()
	_hub_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_panel.add_child(_hub_margin)
	_hub_box = _vbox(_hub_margin, "Box")
	_hub_text = HudTheme.make_label("Drive through a portal!", 32)
	_hub_box.add_child(_hub_text)
	_hub_worlds = _hbox(_hub_box, "Worlds")
	for w in WORLD_ICONS:
		var wb := _vbox(_hub_worlds, w["id"])
		wb.add_theme_constant_override("separation", 0)
		var ic := HudTheme.make_label(w["icon"], 36, Color.WHITE, false)
		ic.tooltip_text = w["label"]
		wb.add_child(ic)
		var sr := _hbox(wb, "Stars")
		sr.add_theme_constant_override("separation", 0)
		var star_lbls := []
		for i in 3:
			var sl := HudTheme.make_label("★", 16, Color(1, 1, 1, 0.3), false)
			sr.add_child(sl)
			star_lbls.append(sl)
		_hub_world_nodes.append({"id": w["id"], "icon": ic, "stars": star_lbls})

	# ------------------------------------------------------------------- race
	var race := _screen("race")
	_pos_badge = HudBadge.new()
	_pos_badge.tile_icon = "flag"
	race.add_child(_pos_badge)
	_lap_badge = HudBadge.new()
	_lap_badge.tile_icon = "lap"
	race.add_child(_lap_badge)
	_timer_badge = HudBadge.new()
	_timer_badge.tile_icon = "clock"
	_timer_badge.min_value_em = 4.6
	_timer_badge.align_right = true
	race.add_child(_timer_badge)
	_gate = HudIcon.new()
	_gate.icon = "chevron"
	_gate.color = HudTheme.GREEN
	_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race.add_child(_gate)
	_pitch = HudTheme.make_label("", 18)
	_pitch.visible = false
	race.add_child(_pitch)
	_wrong = HudPanel.new()
	_wrong.stops = [Color("ff7a7a"), Color("e03434")]
	_wrong.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrong.visible = false
	race.add_child(_wrong)
	_wrong_label = HudTheme.make_label("WRONG WAY!", 32)
	_wrong_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wrong.add_child(_wrong_label)
	_speedo = HudSpeedo.new()
	race.add_child(_speedo)
	_depth = HudBadge.new()
	_depth.tile_icon = "txt:🤿"
	_depth.visible = false
	race.add_child(_depth)
	_count = HudTheme.make_label("", 200, HudTheme.YELLOW)
	_count.visible = false
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	race.add_child(_count)

	# ---------------------------------------------------------------- results
	var res := _screen("results")
	_dim(res, Color(4.0 / 255, 50.0 / 255, 90.0 / 255, 0.35), Color(2.0 / 255, 20.0 / 255, 42.0 / 255, 0.75), 0.4)
	_results_confetti = _ctl(res, "Confetti")
	_results_confetti.draw.connect(_draw_confetti)
	_results_card = HudPanel.new()
	_results_card.name = "Card"
	_results_card.stops = [Color(16.0 / 255, 92.0 / 255, 156.0 / 255, 0.92), Color(6.0 / 255, 42.0 / 255, 78.0 / 255, 0.95)]
	_results_card.mouse_filter = Control.MOUSE_FILTER_STOP
	res.add_child(_results_card)
	_results_margin = MarginContainer.new()
	_results_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_card.add_child(_results_margin)
	_results_box = _vbox(_results_margin, "Box")
	_results_title = _hbox(_results_box, "Title")
	_results_title.add_theme_constant_override("separation", 0)
	_results_t1 = HudTheme.make_label("You finished ", 40)
	_results_place = HudTheme.make_label("1st", 46, HudTheme.YELLOW)
	_results_t2 = HudTheme.make_label("!", 40)
	_results_title.add_child(_results_t1)
	_results_title.add_child(_results_place)
	_results_title.add_child(_results_t2)
	_results_stars = _hbox(_results_box, "Stars")
	for i in 3:
		var st := HudIcon.new()
		st.icon = "star"
		st.color = Color(1, 1, 1, 0.18)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_results_stars.add_child(st)
		_star_icons.append(st)
	_results_times = _hbox(_results_box, "Times")
	for pair in [["TIME", "time"], ["BEST", "best"]]:
		var vb := _vbox(_results_times, pair[1])
		vb.add_theme_constant_override("separation", 2)
		var lbl := HudTheme.make_label(pair[0], 16, HudTheme.PALE, false)
		vb.add_child(lbl)
		_results_lbls.append(lbl)
		var val := HudTheme.make_label("00:00.0", 34)
		vb.add_child(val)
		if pair[1] == "time":
			_results_time = val
		else:
			_results_best = val
	_results_btns = _hbox(_results_box, "Buttons")
	_results_again = _btn(_results_btns, "Again", "yellow", "pill", "reset", "Race again", "raceAgain")
	_results_exit = _btn(_results_btns, "Exit", "blue", "pill", "anchor", "Back to harbour", "exit")

	# ----------------------------------------------------------------- paused
	var pau := _screen("paused")
	var pdim := ColorRect.new()
	pdim.color = Color(2.0 / 255, 18.0 / 255, 38.0 / 255, 0.66)
	pdim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pdim.mouse_filter = Control.MOUSE_FILTER_STOP
	pau.add_child(pdim)
	_pause_card = HudPanel.new()
	_pause_card.name = "Card"
	_pause_card.stops = [Color(16.0 / 255, 92.0 / 255, 156.0 / 255, 0.92), Color(6.0 / 255, 42.0 / 255, 78.0 / 255, 0.95)]
	_pause_card.mouse_filter = Control.MOUSE_FILTER_STOP
	pau.add_child(_pause_card)
	_pause_margin = MarginContainer.new()
	_pause_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_card.add_child(_pause_margin)
	_pause_box = _vbox(_pause_margin, "Box")
	_pause_h = HudTheme.make_label("Paused", 40)
	_pause_box.add_child(_pause_h)
	for spec in [["Resume", "green", "play", "Resume", "resume"], ["Garage", "yellow", "txt:🚤", "Change boat", "garage"], ["Exit", "blue", "anchor", "Back to harbour", "exit"], ["Quit", "red", "txt:✖", "Quit game", "quit"]]:
		var b := _btn(_pause_box, spec[0], spec[1], "pill", spec[2], spec[3], spec[4])
		b.align_start = true
		b.size_flags_horizontal = Control.SIZE_FILL
		_pause_btns.append(b)
	_pause_row = _hbox(_pause_box, "Row")
	for spec in [["camera", "camera"], ["reset", "reset"], ["mute", "sound"], ["tilt", "tilt"], ["fullscreen", "full"], ["matte", "water"]]:
		var b := _btn(_pause_row, spec[0], "sys", "circle", spec[1], "", spec[0])
		_pause_sys[spec[0]] = b
	_pause_sys["tilt"].visible = touch

	# ---------------------------------------------------------- always-on
	_sys = _hbox(_root, "Sys")
	_sys.visible = false
	for spec in [["camera", "camera"], ["reset", "reset"], ["mute", "sound"], ["pause", "pause"], ["exit", "home"]]:
		var b := _btn(_sys, spec[0], "sys", "circle", spec[1], "", spec[0])
		_sys_btns[spec[0]] = b
	_sys_btns["exit"].style = "home"

	_touch = _ctl(_root, "Touch")
	_touch.visible = false
	_wheel = HudIcon.new()
	_wheel.icon = "wheel"
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch.add_child(_wheel)
	_touch_ctls["wheel"] = _wheel
	for spec in [["up", "dive", "up"], ["left", "arrow", "left"], ["right", "arrow", "right"], ["down", "dive", "down"]]:
		var b := _btn(_touch, spec[0], spec[1], "rrect", spec[2])
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_touch_ctls[spec[0]] = b
	var hornb := _btn(_touch, "horn", "horn", "circle", "horn")
	hornb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ctls["horn"] = hornb
	var boostb := _btn(_touch, "boost", "boost", "circle", "bolt")
	boostb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ctls["boost"] = boostb
	var brake := _btn(_touch, "brake", "stop", "pedal", "", "STOP")
	brake.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ctls["brake"] = brake
	var thr := _btn(_touch, "throttle", "go", "pedal", "", "GO")
	thr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ctls["throttle"] = thr

	_keys_panel = HudPanel.new()
	_keys_panel.name = "Keys"
	_keys_panel.stops = [HudTheme.NAVY, HudTheme.NAVY]
	_keys_panel.border_color = Color(1, 1, 1, 0.5)
	_keys_panel.drop = 0.0
	_keys_panel.soft = 0.0
	_keys_panel.highlight = 0.0
	_keys_panel.visible = false
	_keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_keys_panel)
	_keys = RichTextLabel.new()
	_keys.bbcode_enabled = true
	_keys.fit_content = true
	_keys.scroll_active = false
	_keys.autowrap_mode = TextServer.AUTOWRAP_OFF
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.add_theme_font_override("normal_font", HudTheme.font())
	_keys.add_theme_color_override("default_color", Color.WHITE)
	_keys_panel.add_child(_keys)

	_toast_box = _ctl(_root, "Toasts", false)
	_rotate = _ctl(_root, "Rotate")
	_rotate.visible = false
	var rg := Gradient.new()
	rg.set_color(0, Color("37b9ff"))
	rg.set_color(1, Color("045a8d"))
	var rtex := GradientTexture2D.new()
	rtex.gradient = rg
	rtex.fill_from = Vector2(0.5, 0)
	rtex.fill_to = Vector2(0.5, 1)
	var rtr := TextureRect.new()
	rtr.texture = rtex
	rtr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rtr.mouse_filter = Control.MOUSE_FILTER_STOP
	_rotate.add_child(rtr)
	var rbox := _vbox(_rotate, "Box")
	rbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rotate_icon = HudTheme.make_label("📱", 100, Color.WHITE, false)
	_rotate_label = HudTheme.make_label("Turn your tablet sideways!", 30)
	rbox.add_child(_rotate_icon)
	rbox.add_child(_rotate_label)


# ========================================================================== layout
func _metrics() -> Dictionary:
	var vp := _root.size
	if vp.x < 2.0 or vp.y < 2.0:
		vp = Vector2(1280, 720)
	var win := Vector2(DisplayServer.window_get_size())
	if win.y < 2.0:
		win = vp
	var scale := maxf(1.0, maxf(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi() / 96.0))
	var css_h := win.y / scale
	var k := vp.y / css_h
	var css_w := vp.x / k
	var vmin := minf(css_w, css_h) / 100.0
	var compact := css_h <= 520.0
	var short := css_h <= 640.0
	var pad := clampf(2.0 * vmin, 10, 26)
	var btn := clampf(12.0 * vmin, 68, 120)
	var sys := clampf(8.0 * vmin, 56, 76)
	var speedo := clampf(27.0 * vmin, 150, 280)
	var gate := clampf(12.0 * vmin, 64, 128)
	var badge_fs := clampf(4.6 * vmin, 24, 50)
	if short:
		pad = 10.0
		btn = clampf(11.0 * vmin, 64, 90)
		speedo = clampf(24.0 * vmin, 140, 200)
	if compact:
		btn = 54.0
		sys = 40.0
		pad = 8.0
		speedo = 96.0
		gate = 44.0
		badge_fs = 17.0
	return {
		"W": vp.x, "H": vp.y, "k": k, "css_w": css_w, "css_h": css_h, "vmin": vmin,
		"compact": compact, "short": short,
		"pad": pad * k, "btn": btn * k, "sys": sys * k, "speedo": speedo * k, "gate": gate * k, "badge_fs": badge_fs * k,
		"gap": clampf(1.4 * vmin, 8, 16) * k,
	}


func _cl(lo: float, v: float, hi: float) -> float:
	return clampf(v * _m["vmin"], lo, hi) * _m["k"]


func _center(c: Control, w: float, h: float, cx: float, cy: float) -> void:
	c.size = Vector2(w, h)
	c.position = Vector2(cx - w * 0.5, cy - h * 0.5)


func _fit_box(panel: Control, margin: MarginContainer, pad_x: float, pad_y: float) -> Vector2:
	margin.add_theme_constant_override("margin_left", int(pad_x))
	margin.add_theme_constant_override("margin_right", int(pad_x))
	margin.add_theme_constant_override("margin_top", int(pad_y))
	margin.add_theme_constant_override("margin_bottom", int(pad_y))
	var ms := margin.get_combined_minimum_size()
	margin.position = Vector2.ZERO
	margin.size = ms
	panel.size = ms + Vector2(0, panel.drop if panel is HudPanel else 0.0)
	return panel.size


func _layout() -> void:
	_layout_dirty = false
	_m = _metrics()
	var m := _m
	_compact = m["compact"]
	var k: float = m["k"]
	var W: float = m["W"]
	var H: float = m["H"]
	var pad: float = m["pad"]
	var btn: float = m["btn"]
	var sys: float = m["sys"]
	var gap: float = m["gap"]

	# ---- title
	var L := _cl(52, 13, 150)
	_title_logo.set_font_size(L)
	_title_logo_wrap.custom_minimum_size = _title_logo.size
	_title_logo.position = Vector2.ZERO
	var boat_fs := _cl(28, 6, 64)
	for l: Label in _title_boats:
		HudTheme.style_label(l, boat_fs, Color.WHITE, false)
		var ms := l.get_combined_minimum_size()
		l.get_parent().custom_minimum_size = ms
		l.size = ms
		l.position = Vector2.ZERO
	_title_boats_row.add_theme_constant_override("separation", int(boat_fs * 1.2))
	_title_play.font_size = _cl(34, 7.5, 80)
	_title_play.min_height = btn
	_title_play.pad_x = 1.15
	HudTheme.style_label(_title_tap, _cl(16, 2.6, 26), Color(1, 1, 1, 0.85), false)
	_title_box.add_theme_constant_override("separation", int(_cl(8, 2, 24)))
	var ts := _title_box.get_combined_minimum_size()
	_title_box.size = ts
	_title_box.position = Vector2((W - ts.x) * 0.5, (H - ts.y) * 0.5)
	_title_corner.add_theme_constant_override("separation", int(gap))
	for b in _title_corner.get_children():
		b.custom_minimum_size = Vector2(sys, sys)
	var cs := _title_corner.get_combined_minimum_size()
	_title_corner.size = cs
	_title_corner.position = Vector2(W - pad - cs.x, pad)

	# ---- garage
	HudTheme.style_label(_garage_h, _cl(30, 6, 64))
	_garage_box.add_theme_constant_override("separation", int(6.0 * k if m["short"] else _cl(8, 1.8, 22)))
	var row_gap := _cl(8, 1.6, 20)
	_garage_row.add_theme_constant_override("separation", int(row_gap))
	_garage_prev.custom_minimum_size = Vector2(btn, btn)
	_garage_next.custom_minimum_size = Vector2(btn, btn)
	var row_w := minf(W - pad * 2.0, 1500.0 * k)
	var card_w := minf(clampf(17.0 * m["css_w"] / 100.0, 140, 300), 320) * k
	var card_h := 0.0
	_garage_cards.add_theme_constant_override("separation", int(row_gap))
	for c in _cards:
		c.size.x = card_w
		c.custom_minimum_size.x = card_w
		c.layout(k, m["vmin"] * 100.0, m["short"])
		card_h = maxf(card_h, c.size.y)
	for c in _cards:
		# align-items: stretch — every card gets the tallest card's height
		c.custom_minimum_size = Vector2(card_w, card_h)
		c.size = Vector2(card_w, card_h)
		c.pivot_offset = c.size * 0.5
	var cards_pad := _cl(10, 2, 24)
	_garage_scroll.custom_minimum_size = Vector2(row_w - (btn + row_gap) * 2.0, card_h * 1.06 + cards_pad)
	_garage_cards.custom_minimum_size = Vector2(_garage_scroll.custom_minimum_size.x, card_h * 1.06 + cards_pad)
	_garage_foot.add_theme_constant_override("separation", int(_cl(16, 4, 48)))
	_garage_swatches.add_theme_constant_override("separation", int(_cl(8, 1.4, 16)))
	var sw := _cl(48, 8, 72)
	for s in _garage_swatches.get_children():
		s.custom_minimum_size = Vector2(sw, sw)
	_garage_go.font_size = _cl(32, 6.5, 68)
	_garage_go.min_height = btn
	_garage_go.pad_x = 1.4
	var gs := _garage_box.get_combined_minimum_size()
	_garage_box.size = gs
	_garage_box.position = Vector2((W - gs.x) * 0.5, (H - gs.y) * 0.5)

	# ---- hub
	_hub_panel.radius = _cl(18, 3, 32)
	_hub_panel.border = _cl(3, 0.5, 6)
	_hub_panel.drop = 6.0 * k
	_hub_panel.soft = 24.0 * k
	HudTheme.style_label(_hub_text, _cl(24, 4.4, 48))
	_hub_box.add_theme_constant_override("separation", int(_cl(6, 1.2, 14)))
	_hub_worlds.add_theme_constant_override("separation", int(_cl(14, 3, 36)))
	for wn in _hub_world_nodes:
		HudTheme.style_label(wn["icon"], _cl(28, 5.2, 56), Color.WHITE, false)
		for sl in wn["stars"]:
			var lit: bool = sl.get_meta("lit", false)
			HudTheme.style_label(sl, _cl(13, 2.2, 22), HudTheme.YELLOW if lit else Color(1, 1, 1, 0.3), lit)
	var hs := _fit_box(_hub_panel, _hub_margin, _cl(18, 3.4, 40), _cl(8, 1.6, 18))
	_hub_panel.position = Vector2((W - hs.x) * 0.5, pad)
	_hub_panel.set_meta("base_y", pad)

	# ---- race
	var bfs: float = m["badge_fs"]
	for b in [_pos_badge, _lap_badge, _timer_badge]:
		b.fs = bfs
		b.size = b.get_combined_minimum_size()
	_pos_badge.position = Vector2(pad, pad)
	_timer_badge.position = Vector2(W - pad - _timer_badge.size.x, pad)
	var mid_gap := _cl(6, 1.2, 14)
	_lap_badge.position = Vector2((W - _lap_badge.size.x) * 0.5, pad)
	var g: float = m["gate"]
	_gate.size = Vector2(g, g)
	_gate.position = Vector2((W - g) * 0.5, _lap_badge.position.y + _lap_badge.size.y + mid_gap)
	_gate.pivot_offset = Vector2(g, g) * 0.5
	HudTheme.style_label(_pitch, _cl(14, 2.2, 24))
	_pitch.size = Vector2(g * 3.0, _cl(14, 2.2, 24) * 1.3)
	_pitch.position = Vector2((W - _pitch.size.x) * 0.5, _gate.position.y + g + 2.0 * k)
	var wfs := bfs
	HudTheme.style_label(_wrong_label, wfs)
	_wrong.size = Vector2(HudTheme.text_width("WRONG WAY!", wfs) + wfs * 1.4, wfs * 1.4 + wfs * 0.15)
	_wrong.radius = _wrong.size.y * 0.5
	_wrong.border = wfs * 0.1
	_wrong.drop = wfs * 0.15
	_wrong.soft = wfs * 0.5
	_wrong.pivot_offset = _wrong.size * 0.5
	_wrong.set_meta("base_pos", Vector2((W - _wrong.size.x) * 0.5, _gate.position.y + g + mid_gap))
	_wrong.position = _wrong.get_meta("base_pos")
	var sp: float = m["speedo"]
	_speedo.size = Vector2(sp, sp)
	var sp_bottom := (6.0 * k) if _compact else pad * 0.6
	_speedo.position = Vector2((W - sp) * 0.5, H - sp_bottom - sp)
	_depth.fs = (15.0 * k) if _compact else _cl(18, 3.2, 34)
	_depth.size = _depth.get_combined_minimum_size()
	if _compact:
		_depth.position = Vector2((W - _depth.size.x) * 0.5, (8.0 + 44.0) * k)
	else:
		_depth.position = Vector2(W * 0.5 + _cl(90, 15, 150), H - pad * 0.6 - _cl(40, 7, 80) - _depth.size.y)
	HudTheme.style_label(_count, _cl(120, 34, 380), HudTheme.GREEN if _count_go else HudTheme.YELLOW)
	_count.pivot_offset = Vector2(W, H) * 0.5

	# ---- results
	_results_card.radius = _cl(22, 4, 40)
	_results_card.border = _cl(4, 0.7, 8)
	_results_card.drop = _cl(6, 1, 12)
	_results_card.soft = 40.0 * k
	_results_box.add_theme_constant_override("separation", int(8.0 * k if m["short"] else _cl(8, 1.8, 22)))
	var rt := _cl(30, 6.2, 68)
	HudTheme.style_label(_results_t1, rt)
	HudTheme.style_label(_results_place, rt * 1.15, HudTheme.YELLOW)
	HudTheme.style_label(_results_t2, rt)
	_results_stars.add_theme_constant_override("separation", int(_cl(6, 1.2, 14)))
	var ssz := _cl(60, 11, 100) if m["short"] else _cl(72, 14, 150)
	for i in _star_icons.size():
		var st: HudIcon = _star_icons[i]
		st.custom_minimum_size = Vector2(ssz, ssz)
		st.size = Vector2(ssz, ssz)
		st.pivot_offset = Vector2(ssz, ssz) * 0.5
	_results_times.add_theme_constant_override("separation", int(_cl(20, 5, 60)))
	for l in _results_lbls:
		HudTheme.style_label(l, _cl(14, 2.2, 22), HudTheme.PALE, false)
	HudTheme.style_label(_results_time, _cl(26, 4.8, 52))
	HudTheme.style_label(_results_best, _cl(26, 4.8, 52))
	_results_btns.add_theme_constant_override("separation", int(_cl(12, 2.5, 28)))
	for b in [_results_again, _results_exit]:
		b.font_size = _cl(20, 3.6, 38)
		b.min_height = btn
	var rmin := minf(0.9 * W, 620.0 * k)
	var rs := _fit_box(_results_card, _results_margin, _cl(22, 4.5, 56), _cl(18, 3.4, 40))
	if rs.x < rmin:
		_results_margin.size.x = rmin
		_results_card.size.x = rmin
		rs.x = rmin
	_results_card.pivot_offset = rs * 0.5
	_results_card.set_meta("base_pos", Vector2((W - rs.x) * 0.5, (H - rs.y) * 0.5))
	_results_card.position = _results_card.get_meta("base_pos")

	# ---- paused
	_pause_card.radius = _cl(22, 4, 40)
	_pause_card.border = _cl(4, 0.7, 8)
	_pause_card.drop = _cl(6, 1, 12)
	_pause_card.soft = 40.0 * k
	_pause_box.add_theme_constant_override("separation", int(_cl(10, 1.8, 20)))
	HudTheme.style_label(_pause_h, _cl(30, 6, 64))
	for b in _pause_btns:
		b.font_size = _cl(22, 4.2, 44)
		b.min_height = btn
	_pause_row.add_theme_constant_override("separation", int(_cl(10, 2, 22)))
	for b in _pause_row.get_children():
		b.custom_minimum_size = Vector2(sys, sys)
	var pmin := minf(0.88 * W, 520.0 * k)
	var ps := _fit_box(_pause_card, _pause_margin, _cl(22, 4.5, 56), _cl(18, 3.4, 40))
	if ps.x < pmin:
		_pause_margin.size.x = pmin
		_pause_card.size.x = pmin
		ps.x = pmin
	_pause_card.pivot_offset = ps * 0.5
	_pause_card.position = Vector2((W - ps.x) * 0.5, (H - ps.y) * 0.5)

	# ---- sys row
	_sys.add_theme_constant_override("separation", int((6.0 * k) if _compact else gap))
	for n in _sys_btns:
		var b: HudButton = _sys_btns[n]
		b.custom_minimum_size = Vector2(sys, sys)
		b.visible = not (_compact and n in ["camera", "reset", "mute"]) and not (n == "exit" and screen != "race")
	var ss := _sys.get_combined_minimum_size()
	_sys.size = ss
	var sys_top := pad + bfs * 1.9 + _cl(8, 1.5, 16)
	if _compact:
		sys_top = (8.0 + 46.0) * k
	if screen == "hub":
		sys_top = (8.0 * k) if _compact else pad
	_sys.position = Vector2(W - pad - ss.x, sys_top)

	# ---- touch controls
	var tgap := (8.0 * k) if _compact else _cl(10, 2, 24)
	var left := (10.0 * k) if _compact else pad
	var bottom := (10.0 * k) if _compact else pad + 6.0 * k
	var wheel_sz := btn * 1.9
	_wheel.visible = not _compact
	_wheel.size = Vector2(wheel_sz, wheel_sz)
	_wheel.position = Vector2(left, H - bottom - wheel_sz)
	_wheel.pivot_offset = _wheel.size * 0.5
	var ax := left + (wheel_sz + tgap if not _compact else 0.0)
	var arrows := ["up", "left", "right", "down"]
	if _sub:
		var dg := _cl(6, 1.2, 14)
		var base_y := H - bottom - (btn * 3.0 + dg * 2.0)
		_touch_ctls["up"].position = Vector2(ax + btn + dg, base_y)
		_touch_ctls["left"].position = Vector2(ax, base_y + btn + dg)
		_touch_ctls["right"].position = Vector2(ax + (btn + dg) * 2.0, base_y + btn + dg)
		_touch_ctls["down"].position = Vector2(ax + btn + dg, base_y + (btn + dg) * 2.0)
	else:
		_touch_ctls["left"].position = Vector2(ax, H - bottom - btn)
		_touch_ctls["right"].position = Vector2(ax + btn + tgap, H - bottom - btn)
	for n in arrows:
		var b: HudButton = _touch_ctls[n]
		b.size = Vector2(btn, btn)
		b.visible = _sub or n in ["left", "right"]
	var col1 := (44.0 * k) if _compact else btn
	var col2 := (62.0 * k) if _compact else btn * 1.15
	var row1 := (44.0 * k) if _compact else btn
	var row2 := (84.0 * k) if _compact else btn * 1.5
	var round_sz := (44.0 * k) if _compact else btn
	var rx := W - ((10.0 * k) if _compact else pad)
	var ry := H - bottom
	var x2 := rx - col2
	var x1 := x2 - tgap - col1
	var y2 := ry - row2
	var y1 := y2 - tgap - row1
	_touch_ctls["horn"].size = Vector2(round_sz, round_sz)
	_touch_ctls["horn"].position = Vector2(x1 + col1 - round_sz, y1 + row1 - round_sz)
	_touch_ctls["boost"].size = Vector2(round_sz, round_sz)
	_touch_ctls["boost"].position = Vector2(x2 + col2 - round_sz, y1 + row1 - round_sz)
	var brake_h := row2 if _compact else btn * 1.05
	_touch_ctls["brake"].size = Vector2(col1, brake_h)
	_touch_ctls["brake"].position = Vector2(x1, ry - brake_h)
	_touch_ctls["throttle"].size = Vector2(col2, row2)
	_touch_ctls["throttle"].position = Vector2(x2, y2)
	var pedal_fs := (12.0 * k) if _compact else _cl(16, 2.6, 26)
	_touch_ctls["brake"].font_size = pedal_fs
	_touch_ctls["throttle"].font_size = pedal_fs

	# ---- key hints
	var kfs := _cl(14, 2, 20)
	_keys.add_theme_font_size_override("normal_font_size", int(kfs))
	_keys.add_theme_font_size_override("bold_font_size", int(kfs))
	var bb := _keys_bbcode()
	if _keys.text != bb:
		_keys.text = bb
	_layout_keys()

	# ---- toasts / rotate
	_toast_box.position = Vector2(0, H * 0.3)
	_toast_box.size = Vector2(W, H * 0.4)
	for t in _toasts:
		var l: Label = t["node"]
		HudTheme.style_label(l, (18.0 * k) if _compact else _cl(44, 10, 120), t["color"])
	HudTheme.style_label(_rotate_icon, _cl(60, 20, 160), Color.WHITE, false)
	HudTheme.style_label(_rotate_label, clampf(6.0 * m["css_w"] / 100.0, 22, 40) * k)
	_rotate.visible = touch and W < H and m["css_w"] < 900.0


func _layout_keys() -> void:
	var k: float = _m["k"]
	var kfs := _cl(14, 2, 20)
	var kp := Vector2(kfs * 1.0, kfs * 0.5)
	_keys.position = kp
	var ks := _keys.get_combined_minimum_size()
	if ks.x < 10:
		ks = Vector2(kfs * 30, kfs * 1.4)
	_keys.size = ks
	_keys_panel.size = ks + kp * 2.0
	_keys_panel.radius = _keys_panel.size.y * 0.5
	_keys_panel.border = 2.0 * k
	var kb: float = _m["pad"] * 0.6 + _m["speedo"] + 14.0 * k
	if screen == "hub":
		kb = _m["pad"] * 3.0
	_keys_panel.position = Vector2((_m["W"] - _keys_panel.size.x) * 0.5, _m["H"] - kb - _keys_panel.size.y)
	_keys_panel.visible = _hint_t >= 0.0 and not _compact and PLAY_SCREENS.has(screen)


func _keys_bbcode() -> String:
	var kbd := func(s: String) -> String:
		return "[bgcolor=#ffffff][color=#05324f] %s [/color][/bgcolor]" % s
	var parts := [
		"%s%s%s%s or arrows to drive" % [kbd.call("W"), kbd.call("A"), kbd.call("S"), kbd.call("D")],
		"%s boost" % kbd.call("Space"),
	]
	if _sub:
		parts.append("%s dive %s rise" % [kbd.call("Q"), kbd.call("E")])
	parts.append("%s camera" % kbd.call("C"))
	parts.append("%s reset" % kbd.call("R"))
	parts.append("%s pause" % kbd.call("Esc"))
	return "[center]" + "    ".join(parts) + "[/center]"


# ============================================================================ API
## Replace the garage catalogue. `list` is an Array of boat dictionaries (id, label, icon,
## description, colors, stats) or a Dictionary keyed by id; missing fields come from DEFAULT_BOATS.
func set_boats(list: Variant) -> void:
	var out: Array = []
	if list is Array:
		for b in list:
			out.append(_merge_boat(b))
	elif list is Dictionary:
		for id in list:
			var b: Dictionary = (list[id] as Dictionary).duplicate()
			b["id"] = id
			out.append(_merge_boat(b))
	if out.is_empty():
		return
	boats = out
	var ok := false
	for b in boats:
		if b["id"] == selected_boat:
			ok = true
	if not ok:
		selected_boat = boats[0]["id"]
	if is_inside_tree():
		_render_cards()


func _merge_boat(b: Dictionary) -> Dictionary:
	var out := {}
	for d in DEFAULT_BOATS:
		if d["id"] == b.get("id", ""):
			out = d.duplicate(true)
	for key in b:
		out[key] = b[key]
	var cols: Array = []
	for c in out.get("colors", []):
		cols.append(HudTheme.to_color(c))
	out["colors"] = cols
	return out


## map = { worldId: 3 } or { worldId: { stars: 3, best: 81.2 } }
func set_stars(map: Dictionary) -> void:
	stars = {}
	for key in map:
		var v = map[key]
		stars[key] = int(v) if (v is int or v is float) else int((v as Dictionary).get("stars", 0))
	if is_inside_tree():
		_render_world_stars()


func set_muted(m: bool) -> void:
	muted = m
	for b in _mute_btns:
		b.icon = "muted" if muted else "sound"
		b.off = muted


func set_matte(on: bool) -> void:
	matte_on = on
	if _pause_sys.has("matte"):
		_pause_sys["matte"].toggled = on


## Tilt steering (touch devices): while on, the accelerometer feeds Controls.set_tilt() each frame.
func set_tilt(on: bool) -> void:
	tilt_on = on
	if _pause_sys.has("tilt"):
		_pause_sys["tilt"].toggled = on
	if not on and _controls != null and _controls.has_method("clear_tilt"):
		_controls.clear_tilt()
	tilt.emit(on)


## Big centred pop-up text (LAP 2!, FINAL LAP!). `final` uses the orange colour.
func toast(text: String, final := false) -> void:
	var col := HudTheme.ORANGE if final else HudTheme.YELLOW
	var l := HudTheme.make_label(text, 60, col)
	_toast_box.add_child(l)
	_toasts.append({"node": l, "t": 0.0, "color": col})
	if not _m.is_empty():
		HudTheme.style_label(l, (18.0 * _m["k"]) if _compact else _cl(44, 10, 120), col)
	_place_toasts()


func show_screen(n: String, data: Dictionary = {}) -> void:
	if not SCREENS.has(n):
		push_warning("[hud] unknown screen " + n)
		return
	var prev := screen
	screen = n
	_set_screen_visibility()
	var play := PLAY_SCREENS.has(n)
	if not (play and touch):
		_release_all()
	if play and not touch and not _hint_shown:
		_hint_shown = true
		_hint_t = 0.0
	if n == "race" and prev != "race" and prev != "paused":
		_c = {}
		_wrong_t = 0.0
		_count.visible = false
		_count_t = -1.0
		_wrong.visible = false
	if n == "results":
		_show_results(data)
	if n == "garage":
		_render_swatches()
		_scroll_to_selected.call_deferred()
	if n == "paused":
		_pause_t = 0.0
	_layout_dirty = true


func _set_screen_visibility() -> void:
	for s in SCREENS:
		_scr[s].visible = s == screen
	var play := PLAY_SCREENS.has(screen)
	_sys.visible = play
	_touch.visible = play and touch
	_depth.visible = _sub and play


## Called every frame by the game loop. Only touches nodes when a value changes.
func update(f: Dictionary) -> void:
	if not f.is_empty():
		last = f
	if screen != "race" or f.is_empty():
		return
	var c := _c
	var pos := int(f.get("position", 0))
	var racers := int(f.get("racers", 0))
	if pos != c.get("pos", -1) or racers != c.get("racers", -1):
		c["pos"] = pos
		c["racers"] = racers
		_pos_badge.segments = [
			{"text": str(pos) if pos > 0 else "-", "scale": 1.15, "color": HudTheme.YELLOW},
			{"text": "/%d" % racers if racers > 0 else "", "scale": 0.66},
		]
		_layout_dirty = true
	var lap := int(f.get("lap", 0))
	var laps := int(f.get("laps", 0))
	if lap != c.get("lap", -1) or laps != c.get("laps", -1):
		var prev_lap: int = c.get("lap", -1)
		c["lap"] = lap
		c["laps"] = laps
		_lap_badge.segments = [
			{"text": "LAP "},
			{"text": str(maxi(1, lap)), "scale": 1.15, "color": HudTheme.YELLOW},
			{"text": "/%d" % laps if laps > 0 else "", "scale": 0.66},
		]
		_layout_dirty = true
		if prev_lap >= 0 and lap > prev_lap and lap > 1:
			var final := lap >= laps and laps > 0
			toast("FINAL LAP!" if final else "LAP %d!" % lap, final)
	var t := fmt_time(float(f.get("time", 0.0)))
	if t != c.get("time", ""):
		c["time"] = t
		_timer_badge.segments = [{"text": t}]
	# submarine mode
	var sub: bool = bool(f.get("submerged", false))
	if sub != _sub:
		_sub = sub
		_layout_dirty = true
		_depth.visible = _sub
	if sub:
		var d := int(round(float(f.get("depth", 0.0))))
		if d != c.get("depth", -1):
			c["depth"] = d
			_depth.segments = [{"text": str(d), "scale": 1.15, "color": HudTheme.YELLOW}, {"text": " m deep", "scale": 0.66}]
			_layout_dirty = true
	var kmh := int(round(float(f.get("speed_kmh", 0.0))))
	if kmh != c.get("kmh", -1):
		c["kmh"] = kmh
		_speedo.value = kmh
	# next-gate arrow
	var has_dir := f.has("next_gate_dir") and f["next_gate_dir"] != null
	var dt: float = c.get("dt", 0.016)
	if has_dir:
		var dir := float(f["next_gate_dir"])
		if is_nan(dir):
			has_dir = false
		else:
			dir = atan2(sin(dir), cos(dir))
			var deg := int(round(rad_to_deg(dir)))
			if deg != c.get("deg", 999):
				c["deg"] = deg
				_gate.set_angle(dir)
			var off := absf(dir) > 0.75
			if off != c.get("off", null):
				c["off"] = off
				_gate.color = HudTheme.YELLOW if off else HudTheme.GREEN
			if c.get("gate_hidden", true):
				c["gate_hidden"] = false
				_gate.modulate.a = 1.0
			_wrong_t = _wrong_t + dt if (absf(dir) > 2.35 and float(f.get("speed_kmh", 0.0)) > 4.0) else 0.0
			var pitch := float(f.get("next_gate_pitch", 0.0))
			if sub and absf(pitch) > 0.3:
				var txt := "▲ rise" if pitch > 0.0 else "▼ dive"
				if txt != c.get("pitch", ""):
					c["pitch"] = txt
					_pitch.text = txt
					_pitch.visible = true
			elif _pitch.visible:
				c["pitch"] = ""
				_pitch.visible = false
	if not has_dir:
		if not c.get("gate_hidden", true):
			c["gate_hidden"] = true
			_gate.modulate.a = 0.0
		_wrong_t = 0.0
	var wrong := _wrong_t > 2.0
	if wrong != c.get("wrong", false):
		c["wrong"] = wrong
		_wrong.visible = wrong
	# countdown 3 · 2 · 1 · GO!
	var cdv := float(f.get("countdown", 0.0))
	var cd := int(ceil(cdv)) if cdv > 0.0 else 0
	if cd != c.get("cd", -1):
		var prev_cd: int = c.get("cd", -1)
		c["cd"] = cd
		if cd > 0:
			_count_show(str(cd), false)
		elif prev_cd > 0:
			_count_show("GO!", true)
		else:
			_count.visible = false


static func fmt_time(t: float) -> String:
	if not (t >= 0.0):
		t = 0.0
	var m := int(t / 60.0)
	var s := int(fmod(t, 60.0))
	var d := int(fmod(t * 10.0, 10.0))
	return "%02d:%02d.%d" % [m, s, d]


static func ordinal(n: int) -> String:
	var suf := "th"
	if not (n % 100 >= 11 and n % 100 <= 13):
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return str(n) + suf


# ====================================================================== screens
func _show_results(d: Dictionary) -> void:
	var f := last
	var position := int(d.get("place", d.get("position", f.get("position", 1))))
	var st := int(d.get("stars", f.get("stars", maxi(1, 4 - position))))
	_results_stars_n = clampi(st, 0, 3)
	var time := float(d.get("time", f.get("time", 0.0)))
	var best := float(d.get("best", d.get("best_time", f.get("best_time", 0.0))))
	_results_place.text = ordinal(position)
	_results_time.text = fmt_time(time)
	_results_best.text = fmt_time(best) if best > 0.0 else fmt_time(time)
	for i in 3:
		_star_icons[i].color = Color(1, 1, 1, 0.18)
		_star_icons[i].scale = Vector2.ONE * (1.1 if i == 1 else 0.85)
		_star_icons[i].rotation = 0.0
	_star_t = 0.0
	_card_t = 0.0
	if _confetti.is_empty():
		_build_confetti()


func _build_confetti() -> void:
	_confetti.clear()
	for i in 70:
		_confetti.append({
			"x": randf(), "d": randf() * 2.5, "dur": 2.8 + randf() * 2.2,
			"rot": deg_to_rad(randf() * 720.0 - 360.0), "w": 8.0 + randf() * 8.0, "h": 10.0 + randf() * 12.0,
			"col": Color(CONFETTI_COLORS[i % CONFETTI_COLORS.size()]),
		})


func _draw_confetti() -> void:
	if _card_t < 0.0:
		return
	var ci := _results_confetti
	var W := ci.size.x
	var H := ci.size.y
	var k: float = _m.get("k", 1.0)
	for p in _confetti:
		var t: float = _card_t - float(p["d"])
		if t < 0.0:
			continue
		var dur: float = p["dur"]
		var u := fmod(t, dur) / dur
		var y := -20.0 * k + (H + 40.0 * k) * u
		ci.draw_set_transform(Vector2(p["x"] * W, y), p["rot"] * u, Vector2(k, k))
		ci.draw_rect(Rect2(-p["w"] * 0.5, -p["h"] * 0.5, p["w"], p["h"]), p["col"])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _render_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for b in boats:
		var card := HudCard.new()
		card.name = b["id"]
		card.setup(b, b["id"] == selected_boat)
		card.picked.connect(_pick_boat)
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_garage_cards.add_child(card)
		_cards.append(card)
	_render_swatches()
	_layout_dirty = true


func _render_swatches() -> void:
	for s in _garage_swatches.get_children():
		s.queue_free()
	var b := _boat(selected_boat)
	var cols: Array = b.get("colors", [])
	if cols.is_empty():
		cols = [HudTheme.ORANGE]
	if color_index >= cols.size():
		color_index = 0
	for i in cols.size():
		var sw := HudButton.new()
		sw.name = "Swatch%d" % i
		sw.style = "swatch"
		sw.shape = "circle"
		sw.swatch_color = HudTheme.to_color(cols[i])
		sw.toggled = i == color_index
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.pressed.connect(_pick_color.bind(i))
		_garage_swatches.add_child(sw)
	_layout_dirty = true


func _render_world_stars() -> void:
	for wn in _hub_world_nodes:
		var n := int(stars.get(wn["id"], 0))
		for i in 3:
			var sl: Label = wn["stars"][i]
			var lit := i < n
			sl.set_meta("lit", lit)
			sl.add_theme_color_override("font_color", HudTheme.YELLOW if lit else Color(1, 1, 1, 0.3))
	_layout_dirty = true


func _boat(id: String) -> Dictionary:
	for b in boats:
		if b["id"] == id:
			return b
	return boats[0] if boats.size() > 0 else {}


func _cycle(dir: int) -> void:
	var i := 0
	for j in boats.size():
		if boats[j]["id"] == selected_boat:
			i = j
	var n := boats.size()
	_pick_boat(boats[(i + dir + n) % n]["id"])


func _pick_boat(id: String) -> void:
	if _boat(id).get("id", "") != id:
		return
	selected_boat = id
	color_index = 0
	for c in _cards:
		c.selected = c.boat["id"] == id
	_render_swatches()
	_scroll_to_selected.call_deferred()
	select_boat.emit(id, color_index)


func _pick_color(i: int) -> void:
	color_index = i
	_render_swatches()
	select_boat.emit(selected_boat, color_index)


func _scroll_to_selected() -> void:
	for c in _cards:
		if c.selected:
			var target := int(c.position.x + c.size.x * 0.5 - _garage_scroll.size.x * 0.5)
			var tw := create_tween()
			tw.tween_property(_garage_scroll, "scroll_horizontal", maxi(0, target), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _count_show(txt: String, go: bool) -> void:
	_count.text = txt
	_count_go = go
	_count.add_theme_color_override("font_color", HudTheme.GREEN if go else HudTheme.YELLOW)
	_count_t = 0.0
	_count.visible = true
	_count.scale = Vector2.ONE * 2.2
	_count.modulate.a = 0.0


func _place_toasts() -> void:
	var y := 0.0
	for t in _toasts:
		var l: Label = t["node"]
		var ms := l.get_combined_minimum_size()
		l.size = ms
		l.position = Vector2((_toast_box.size.x - ms.x) * 0.5, y)
		l.set_meta("y0", y)
		l.pivot_offset = ms * 0.5
		y += ms.y + 8.0


# ====================================================================== actions
func _act(name: String) -> void:
	match name:
		"play":
			start.emit({"from": "title", "boat": selected_boat, "color": color_index})
		"go":
			select_boat.emit(selected_boat, color_index)
			start.emit({"from": "garage", "boat": selected_boat, "color": color_index})
		"prevBoat":
			_cycle(-1)
		"nextBoat":
			_cycle(1)
		"pause":
			pause.emit()
		"resume":
			resume.emit()
		"camera":
			camera.emit()
		"reset":
			reset.emit()
		"exit":
			exit.emit()
		"raceAgain":
			race_again.emit()
		"garage":
			garage.emit()
		"mute":
			set_muted(not muted)
			mute.emit(muted)
		"tilt":
			set_tilt(not tilt_on)
		"matte":
			matte.emit()
		"fullscreen":
			_toggle_fullscreen()
			fullscreen.emit()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_act("play")
	elif event is InputEventScreenTouch and not event.pressed:
		_act("play")


# ======================================================================== input
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		match screen:
			"title":
				if kc == KEY_ENTER or kc == KEY_SPACE or kc == KEY_KP_ENTER:
					_act("play")
			"garage":
				if kc == KEY_ENTER or kc == KEY_KP_ENTER:
					_act("go")
				elif kc == KEY_LEFT:
					_cycle(-1)
				elif kc == KEY_RIGHT:
					_cycle(1)
			"results":
				if kc == KEY_ENTER or kc == KEY_KP_ENTER:
					_act("raceAgain")
		return
	if not (_touch.visible):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	elif event is InputEventScreenDrag:
		_finger_move(event.index, event.position)
	elif not _real_touch:
		# Desktop testing with --touch: the mouse is finger -1.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_finger_down(-1, event.position)
			else:
				_finger_up(-1)
		elif event is InputEventMouseMotion and _fingers.has(-1):
			_finger_move(-1, event.position)


func _hit_ctl(pos: Vector2) -> String:
	for n in _touch_ctls:
		var c: Control = _touch_ctls[n]
		if c.visible and c.get_global_rect().grow(4.0).has_point(pos):
			return n
	return ""


func _finger_down(idx: int, pos: Vector2) -> void:
	var ctl := _hit_ctl(pos)
	if ctl == "":
		return
	_fingers[idx] = ctl
	var node: Control = _touch_ctls[ctl]
	if node is HudButton:
		node.is_down = true
	if ctl == "wheel":
		_wheel_c = _wheel.get_global_rect().get_center()
		_wheel_last_a = atan2(pos.y - _wheel_c.y, pos.x - _wheel_c.x)
		_wheel_drag = true
	elif ctl == "horn":
		_held["horn"] = true
		horn.emit()
	elif _held.has(ctl):
		_held[ctl] = true
	_push_virtual()
	get_viewport().set_input_as_handled()


func _finger_move(idx: int, pos: Vector2) -> void:
	if not _fingers.has(idx) or _fingers[idx] != "wheel":
		return
	var a := atan2(pos.y - _wheel_c.y, pos.x - _wheel_c.x)
	var d := a - _wheel_last_a
	if d > PI:
		d -= TAU
	elif d < -PI:
		d += TAU
	_wheel_last_a = a
	_wheel_angle = clampf(_wheel_angle + rad_to_deg(d), -WHEEL_MAX_DEG, WHEEL_MAX_DEG)
	_wheel.rotation = deg_to_rad(_wheel_angle)
	_push_virtual()
	get_viewport().set_input_as_handled()


func _finger_up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var ctl: String = _fingers[idx]
	_fingers.erase(idx)
	for other in _fingers.values():
		if other == ctl:
			return
	var node: Control = _touch_ctls[ctl]
	if node is HudButton:
		node.is_down = false
	if ctl == "wheel":
		_wheel_drag = false
	elif _held.has(ctl):
		_held[ctl] = false
	_push_virtual()
	get_viewport().set_input_as_handled()


func _release_all() -> void:
	for ctl in _fingers.values():
		var node: Control = _touch_ctls.get(ctl)
		if node is HudButton:
			node.is_down = false
	_fingers.clear()
	for key in _held:
		_held[key] = false
	_wheel_drag = false
	_push_virtual()


func _push_virtual() -> void:
	var h := _held
	var wheel_steer := _wheel_angle / WHEEL_MAX_DEG
	virtual["steer"] = clampf(wheel_steer + (1.0 if h["right"] else 0.0) - (1.0 if h["left"] else 0.0), -1.0, 1.0)
	virtual["throttle"] = 1.0 if h["throttle"] else 0.0
	virtual["brake"] = 1.0 if h["brake"] else 0.0
	virtual["boost"] = h["boost"]
	virtual["dive"] = (1.0 if h["up"] else 0.0) - (1.0 if h["down"] else 0.0)
	virtual["active"] = h["throttle"] or h["brake"] or h["boost"] or h["left"] or h["right"] or h["up"] or h["down"] or _wheel_drag or absf(wheel_steer) > 0.02
	if _controls == null:
		_controls_check += 1
		if _controls_check % 60 == 1:
			_controls = get_node_or_null("/root/Controls")
	if _controls != null:
		if _controls.has_method("set_virtual"):
			_controls.set_virtual(virtual)
		else:
			_controls.set("virtual", virtual)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _touch != null:
			_release_all()


# ==================================================================== animation
func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	_t += dt
	_c["dt"] = dt
	if _layout_dirty:
		_layout()
	# tilt steering → Controls.set_tilt (landscape: gravity along the device's short axis)
	if tilt_on and touch and _touch.visible and _controls != null and _controls.has_method("set_tilt"):
		var g := Input.get_accelerometer()
		if g != Vector3.ZERO:
			_controls.set_tilt(clampf(g.x / 4.5, -1.0, 1.0))
	# touch: wheel spring + virtual push
	if touch:
		if not _wheel_drag and _wheel_angle != 0.0:
			_wheel_angle *= exp(-dt * 9.0)
			if absf(_wheel_angle) < 0.3:
				_wheel_angle = 0.0
			_wheel.rotation = deg_to_rad(_wheel_angle)
		if _touch.visible:
			_push_virtual()
	match screen:
		"title":
			var bob := sin(_t * TAU / 3.2)
			_title_logo.position.y = -bob * 0.015 * _m["H"]
			_title_logo.pivot_offset = _title_logo.size * 0.5
			_title_logo.rotation = deg_to_rad(bob * 1.0)
			for i in _title_boats.size():
				var l: Label = _title_boats[i]
				l.position.y = -sin((_t + 0.8 * i) * TAU / 2.4) * 0.01 * _m["H"]
			_title_play.pivot_offset = _title_play.size * 0.5
			_title_play.scale = Vector2.ONE * (1.03 + 0.03 * sin(_t * TAU / 1.6))
			_title_tap.modulate.a = 0.775 + 0.225 * sin(_t * TAU / 2.0)
		"hub":
			var base_y: float = _hub_panel.get_meta("base_y", _m["pad"])
			_hub_panel.position.y = base_y - sin(_t * TAU / 3.0) * 0.012 * _m["H"]
		"race":
			if _c.get("off", false) and not _c.get("gate_hidden", true):
				var p := 0.5 + 0.5 * sin(_t * TAU / 0.7)
				_gate.modulate = Color(1.0 + 0.25 * p, 1.0 + 0.2 * p, 1.0 - 0.1 * p, 1.0)
			elif _gate.modulate != Color.WHITE and not _c.get("gate_hidden", true):
				_gate.modulate = Color.WHITE
			if _wrong.visible:
				var s := sin(_t * TAU / 0.5)
				_wrong.rotation = deg_to_rad(2.0 * s)
				_wrong.scale = Vector2.ONE * (1.025 + 0.025 * s)
			if _count_t >= 0.0:
				_count_t += dt
				var u := _count_t / 0.9
				if u < 0.35:
					var e := _ease_back(u / 0.35)
					_count.scale = Vector2.ONE * lerpf(2.2, 1.0, e)
					_count.modulate.a = clampf(u / 0.2, 0.0, 1.0)
				elif u < 0.8:
					_count.scale = Vector2.ONE
					_count.modulate.a = 1.0
				elif u < 1.0:
					var e2 := (u - 0.8) / 0.2
					_count.scale = Vector2.ONE * lerpf(1.0, 0.85, e2)
					_count.modulate.a = 1.0 - e2
				else:
					_count_t = -1.0
					_count.visible = false
		"results":
			if _card_t >= 0.0:
				_card_t += dt
				_results_confetti.queue_redraw()
				var u := clampf(_card_t / 0.6, 0.0, 1.0)
				var e := _ease_back(u)
				_results_card.scale = Vector2.ONE * lerpf(0.6, 1.0, e)
				_results_card.modulate.a = clampf(u * 2.0, 0.0, 1.0)
				var base: Vector2 = _results_card.get_meta("base_pos", _results_card.position)
				_results_card.position = base + Vector2(0, lerpf(40.0, 0.0, e))
				for i in 3:
					var st: HudIcon = _star_icons[i]
					var big := i == 1
					if i < _results_stars_n:
						var ts := (_card_t - (0.35 + i * 0.4)) / 0.7
						if ts >= 0.0:
							ts = minf(ts, 1.0)
							st.color = HudTheme.YELLOW
							var target := 1.1 if big else 0.85
							if ts < 0.6:
								var q := _ease_back(ts / 0.6)
								st.scale = Vector2.ONE * lerpf(0.0, target * 1.3, q)
								st.rotation = lerpf(-PI, deg_to_rad(10.0), q)
							else:
								var q2 := (ts - 0.6) / 0.4
								st.scale = Vector2.ONE * lerpf(target * 1.3, target, q2)
								st.rotation = lerpf(deg_to_rad(10.0), 0.0, q2)
		"paused":
			if _pause_t >= 0.0:
				_pause_t += dt
				var u := clampf(_pause_t / 0.4, 0.0, 1.0)
				var e := _ease_back(u)
				_pause_card.scale = Vector2.ONE * lerpf(0.6, 1.0, e)
				_pause_card.modulate.a = clampf(u * 2.0, 0.0, 1.0)
				if u >= 1.0:
					_pause_t = -1.0
	# key hints (7 s)
	if _hint_t >= 0.0:
		_hint_t += dt
		if _hint_t < 0.2:
			_layout_keys()
		var a := 1.0
		if _hint_t < 0.7:
			a = _hint_t / 0.7
		elif _hint_t > 5.25:
			a = clampf((7.0 - _hint_t) / 1.75, 0.0, 1.0)
		_keys_panel.modulate.a = a
		if _hint_t >= 7.0:
			_hint_t = -1.0
			_keys_panel.visible = false
	# toasts
	if not _toasts.is_empty():
		var dead: Array = []
		for t in _toasts:
			t["t"] += dt
			var l: Label = t["node"]
			var u: float = t["t"] / 1.9
			var sc := 1.0
			var rot := 0.0
			var alpha := 1.0
			var dy := 0.0
			if u < 0.25:
				var e := _ease_back(u / 0.25)
				sc = lerpf(0.3, 1.1, e)
				rot = lerpf(-8.0, 2.0, e)
				alpha = clampf(u / 0.15, 0.0, 1.0)
			elif u < 0.4:
				var e2 := (u - 0.25) / 0.15
				sc = lerpf(1.1, 1.0, e2)
				rot = lerpf(2.0, 0.0, e2)
			elif u < 0.8:
				sc = 1.0
			elif u < 1.0:
				var e3 := (u - 0.8) / 0.2
				sc = lerpf(1.0, 1.2, e3)
				alpha = 1.0 - e3
				dy = -40.0 * e3
			else:
				dead.append(t)
				continue
			l.scale = Vector2.ONE * sc
			l.rotation = deg_to_rad(rot)
			l.modulate.a = alpha
			l.position.y = l.get_meta("y0", l.position.y) + dy
		for t in dead:
			_toasts.erase(t)
			t["node"].queue_free()
		if not dead.is_empty():
			_place_toasts()
	if _title_logo.visible:
		_title_logo.queue_redraw()


static func _ease_back(t: float) -> float:
	# cubic-bezier(0.34, 1.56, 0.64, 1) approximation: overshooting ease-out
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := t - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


# ===================================================================== title logo
class HudLogo:
	extends Control
	## "WAVE / RIDERS" wordmark with the animated wave stripe (.wr-logo).
	var fs := 100.0
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_font_size(v: float) -> void:
		fs = v
		var w := HudTheme.text_width("RIDERS", fs * 1.28) * 1.3
		custom_minimum_size = Vector2(w, fs * 0.9 + fs * 1.28 * 0.95 + fs * 0.45)
		size = custom_minimum_size
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt

	func _draw() -> void:
		var cx := size.x * 0.5
		var ink := HudTheme.INK
		var rot := deg_to_rad(-3.0)
		# WAVE
		var y1 := fs * 0.85
		draw_set_transform(Vector2(cx - fs * 0.35, y1), rot, Vector2.ONE)
		HudTheme.draw_text(self, Vector2.ZERO, "WAVE", fs, Color.WHITE, ink, fs * 0.06)
		# RIDERS (yellow → orange gradient approximated with two passes)
		var f2 := fs * 1.28
		var y2 := y1 + f2 * 0.95
		draw_set_transform(Vector2(cx + fs * 0.12, y2), rot, Vector2.ONE)
		HudTheme.draw_text(self, Vector2.ZERO, "RIDERS", f2, Color("ffd84d"), ink, f2 * 0.055)
		var f := HudTheme.font()
		var px := int(round(f2))
		var w := f.get_string_size("RIDERS", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		f.draw_string(get_canvas_item(), Vector2(-w * 0.5, 0), "RIDERS", HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("ffefa8", 0.35))
		# wave stripe
		var sw := size.x * 1.0
		var sh := fs * 0.32
		var y3 := y2 + fs * 0.12
		draw_set_transform(Vector2(cx, y3 + sh * 0.5), rot, Vector2.ONE)
		var band := HudPanel.rrect_points(Rect2(-sw * 0.5, -sh * 0.5, sw, sh), sh * 0.5)
		draw_set_transform(Vector2(cx, y3 + sh * 0.5 + fs * 0.05), rot, Vector2.ONE)
		_wave_fill(band, sw, sh, ink, 0.45, 0.0)
		draw_set_transform(Vector2(cx, y3 + sh * 0.5), rot, Vector2.ONE)
		_wave_fill(band, sw, sh, Color("3ec7ff"), 0.45, 0.0)
		_wave_fill(band, sw, sh, Color(1, 1, 1, 0.9), 0.65, 0.35)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _wave_fill(clip: PackedVector2Array, sw: float, sh: float, col: Color, base: float, phase: float) -> void:
		# polygon under a scrolling sine, intersected with the stripe band (clip by y-band is enough)
		var pts := PackedVector2Array()
		var n := 40
		var top := -sh * 0.5
		for i in n + 1:
			var u := float(i) / float(n)
			var x := -sw * 0.5 + sw * u
			var y := top + sh * (base + 0.3 * sin(u * TAU * 4.5 - _t * 2.1 + phase * TAU))
			pts.append(Vector2(x, y))
		pts.append(Vector2(sw * 0.5, sh * 0.5))
		pts.append(Vector2(-sw * 0.5, sh * 0.5))
		# Clip to the rounded band with Sutherland–Hodgman against the band polygon edges.
		var poly := HudPanel.dedupe(pts)
		var m := clip.size()
		for i in m:
			var a := clip[i]
			var b := clip[(i + 1) % m]
			poly = _clip_edge(poly, a, b)
			if poly.size() < 3:
				return
		poly = HudPanel.dedupe(poly)
		if poly.size() >= 3:
			draw_colored_polygon(poly, col)

	static func _clip_edge(poly: PackedVector2Array, a: Vector2, b: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n := poly.size()
		var e := b - a
		for i in n:
			var p := poly[i]
			var q := poly[(i + 1) % n]
			var sp := e.cross(p - a)
			var sq := e.cross(q - a)
			var pin := sp >= 0.0
			var qin := sq >= 0.0
			if pin:
				out.append(p)
			if pin != qin:
				var t := sp / (sp - sq)
				out.append(p.lerp(q, t))
		return out
