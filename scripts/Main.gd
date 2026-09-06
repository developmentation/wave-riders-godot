extends Node3D
## Main: the game flow state machine and integration point. Port of src/game/Game.js.
##
## Flow: title -> garage -> hub (portals) -> race world -> results -> hub. Every module is
## optional and duck-typed (has_method / get_node_or_null / ResourceLoader.exists), exactly like the
## web Game.js imported its modules dynamically: the core drive loop runs while a module is missing.
## Real modules are preferred; race/stubs/ fill the gaps (StubOcean, StubBoat, StubSub, StubWorld,
## StubFollowCamera, StubHud). Set `force_stubs` (tests) to ignore the real ones.
##
## User args (after `--`, like the web ?skip=): --skip=<world|title>  --boat=<id>  --rubber=0  --matte=1
##   --autopilot=1 (AI drives the player)  --laps=N  --stubs=ocean,boats,world,hud,camera,controls | --stubs=all
## Under the CLI harness with no --skip the game opens in the hub (the web smoke's ?skip=title).

@export var start_world := ""        # "" = title (or hub when there is no real HUD); "title" = hub; a world id = straight into it
@export var start_boat := ""
@export var force_stubs := false      # ignore every real module (all stubs)
@export var stubs := ""               # comma list of modules to stub: ocean,boats,world,hud,camera,controls
@export var ai_rubber_band := true
@export var ai_count := 3
@export var autopilot := false        # the player's boat is AI-driven (harness / screenshots)
@export var laps_override := 0        # > 0 forces the lap count of every race (tests)

var ocean: Node3D
var world: Node
var world_id := ""
var portals: Node
var hud: Node
var audio: Node
var controls: Node
var camera: Camera3D
var boats: Array = []
var player: Node
var race: Race
var state := "boot"          # boot | title | garage | hub | race | results | paused
var time := 0.0
var wind := {"angle": 0.0, "speed": 5.0}
var selected_boat := "speedboat"
var selected_color := 0
var stars: Dictionary = {}
var matte := false
var muted := false

var _paused_state := ""
var _transitioning := false
var _weather: Dictionary = {}
var _boats_node: Node3D
var _fade: ColorRect
var _frame: Dictionary = {}
var _real_hud := false
var _submerged := false
var _env: Environment
var _env_saved: Dictionary = {}
var _ctrl := {"steer": 0.0, "throttle": 0.0, "dive": 0.0, "actions": {}, "enter": false}
var _has := {}
var _transition_portals: Node
var _stub_set: Dictionary = {}
var _quality_arg := ""


# ------------------------------------------------------------------ boot
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("harness_state")
	_parse_args()
	for c in stubs.split(",", false):
		_stub_set[c.strip_edges()] = true
	# Quality: the discrete GPU is the prime target; integrated Intel chips get the 60 fps medium preset.
	if _quality_arg != "":
		Quality.current = _quality_arg
	else:
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		Quality.current = "medium" if ("intel" in adapter or "uhd" in adapter or "iris" in adapter) else "high"
	print("[main] gpu=", RenderingServer.get_video_adapter_name(), " quality=", Quality.current)
	var prefs := SaveData.load_prefs()
	stars = SaveData.load_stars()
	if start_boat != "":
		selected_boat = start_boat
	elif prefs.has("boat"):
		selected_boat = String(prefs.boat)
	var harness := get_node_or_null("/root/Harness")
	if harness:
		harness.process_mode = Node.PROCESS_MODE_ALWAYS

	# Ocean
	ocean = _make("res://ocean/Ocean.tscn")
	if ocean:
		_has["ocean"] = true
		# The real ocean may carry its own sky (WorldEnvironment + sun): drop the scene defaults then.
		# SkyWeather builds its WorldEnvironment/sun in _ready, so test for the node itself, not its children.
		if ocean.get_node_or_null("SkyWeather") != null or not ocean.find_children("*", "WorldEnvironment", true, false).is_empty() or not ocean.find_children("*", "DirectionalLight3D", true, false).is_empty():
			for n in ["WorldEnvironment", "Sun"]:
				var old := get_node_or_null(n)
				if old:
					old.free()
	else:
		ocean = StubOcean.new()
	ocean.name = "Ocean"
	add_child(ocean)
	# Sky (optional module; the tscn carries a default environment + sun)
	var sky := _make("res://scenes/Sky.tscn")
	if sky:
		for n in ["WorldEnvironment", "Sun"]:
			var old := get_node_or_null(n)
			if old:
				old.queue_free()
		sky.name = "Sky"
		add_child(sky)
		if "ocean" in sky:
			sky.ocean = ocean
		_has["sky"] = true
	else:
		var we := get_node_or_null("WorldEnvironment")
		if we:
			_env = we.environment

	_boats_node = Node3D.new()
	_boats_node.name = "Boats"
	add_child(_boats_node)

	# Camera
	var cam := _make("res://scripts/FollowCamera.gd")
	if cam is Camera3D:
		camera = cam
		_has["camera"] = true
	else:
		camera = StubFollowCamera.new()
	camera.name = "FollowCamera"
	if "ocean" in camera:
		camera.ocean = ocean
	add_child(camera)
	camera.current = true
	camera.far = 30000.0   # the cloud dome and far sea reach 14+ km; the default 4 km clipped a band of sky

	# Autoloads
	audio = get_node_or_null("/root/GameAudio")
	if audio:
		_has["audio"] = true
	controls = get_node_or_null("/root/Controls")
	if controls:
		_has["controls"] = true
	if force_stubs or _stub_set.has("controls"):
		controls = null
	if audio and audio.has_method("unlock"):
		audio.unlock()

	# Optional helpers
	if _res("res://boats/Wake.gd") and load("res://boats/Wake.gd").can_instantiate():
		_has["wake"] = true   # one Wake node per boat, see _wake_attach
	# One persistent Portals for the white-out transition (a world's own portals are freed by the
	# switch it is animating); ring detection uses world.portals when the world builds them.
	_transition_portals = _make("res://worlds/Portals.gd")
	if _transition_portals:
		_transition_portals.name = "PortalTransition"
		if "ocean" in _transition_portals:
			_transition_portals.ocean = ocean
		add_child(_transition_portals)
		_has["portals"] = true

	# The harbour hub is where everything starts.
	load_world("hub", true)
	var s := _start_of(_def())
	player = spawn_boat(selected_boat, s.x, s.z, s.heading, selected_color)
	camera.follow(player)
	_wake_attach(player)

	# HUD
	hud = _make("res://ui/Hud.tscn")
	if hud:
		_real_hud = true
		_has["hud"] = true
	else:
		hud = StubHud.new()
	hud.name = "HUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	if "game" in hud:
		hud.game = self
	add_child(hud)
	_wire_hud()
	if hud.has_method("set_stars"):
		hud.set_stars(stars)
	if hud.has_method("set_boats") and _res("res://boats/Boats.gd"):
		var consts: Dictionary = load("res://boats/Boats.gd").get_script_constant_map()
		if consts.has("CATALOG"):
			var list: Array = []
			for b in consts.CATALOG.values():
				if b.get("id", "") != "sub":   # the sub is reached through the Deep Run portal, not the garage
					list.append(b)
			hud.set_boats(list)
			print("[main] garage boats: ", list.size())
	if bool(prefs.get("matte", false)):
		set_matte(true)
	if bool(prefs.get("muted", false)):
		toggle_mute()
	_build_fade()
	print("[main] modules: ", JSON.stringify(_has), " world=", world_id, " boat=", selected_boat)
	start()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		var val := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"--skip":
				start_world = val
			"--boat":
				start_boat = val
			"--rubber":
				ai_rubber_band = val != "0"
			"--matte":
				matte = val != "0"
			"--stubs":
				if val == "" or val == "1" or val == "all":
					force_stubs = true
				else:
					stubs = val
			"--autopilot":
				autopilot = val != "0"
			"--laps":
				laps_override = int(val)
			"--quality":
				_quality_arg = val
	# Under the CLI harness with no --skip, go straight to the hub (the web smoke's ?skip=title).
	if start_world == "" and not OS.get_cmdline_user_args().is_empty():
		start_world = "title"


func _res(path: String) -> bool:
	return not _stubbed(path) and ResourceLoader.exists(path)


func _stubbed(path: String) -> bool:
	if force_stubs:
		return true
	var cat := ""
	if path.begins_with("res://ocean/") or path == "res://scenes/Sky.tscn":
		cat = "ocean"
	elif path.begins_with("res://boats/"):
		cat = "boats"
	elif path.begins_with("res://worlds/"):
		cat = "world"
	elif path.begins_with("res://ui/"):
		cat = "hud"
	elif path.begins_with("res://scripts/FollowCamera"):
		cat = "camera"
	return cat != "" and _stub_set.has(cat)


## Every [ext_resource] of a .tscn must exist, else the scene comes up half-built (a module mid-landing).
func _scene_deps_ok(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var re := RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"(res://[^\"]+)\"")
	for m in re.search_all(f.get_as_text()):
		var dep := m.get_string(1)
		if not ResourceLoader.exists(dep):
			push_warning("[main] %s needs missing %s; using the stub" % [path, dep])
			return false
	return true


## Load a script or scene and instantiate it; null when it is missing or fails to compile (a module
## mid-edit must not take the game down, like the web's optional() imports).
func _make(path: String) -> Node:
	if not _res(path):
		return null
	var res := load(path)
	if res is PackedScene:
		if not (res as PackedScene).can_instantiate() or not _scene_deps_ok(path):
			return null
		return (res as PackedScene).instantiate()
	if res is Script:
		if not (res as Script).can_instantiate():
			push_warning("[main] module %s failed to compile; skipped" % path)
			return null
		return (res as Script).new()
	return null


func start() -> void:
	if start_world == "title" or not _real_hud and start_world == "":
		enter_hub()
	elif start_world != "" and start_world != "hub" and _world_known(start_world):
		enter_world(start_world)
	elif start_world == "hub":
		enter_hub()
	elif start_world == "garage":
		show_garage()
	else:
		show_title()


# ----------------------------------------------------------------- screens
func show_title() -> void:
	state = "title"
	camera.set("orbit", {"angle": 0.6, "dist": 1.6, "height": 0.5, "speed": 0.15, "fov": 42.0})
	_hud_show("title")
	_audio("mood", ["hub"])
	_audio("music", [true])


func show_garage() -> void:
	state = "garage"
	var orbit: Dictionary = camera.get("orbit") if camera.get("orbit") is Dictionary else {}
	camera.set("orbit", {"angle": orbit.get("angle", 0.6), "dist": 1.7, "height": 0.45, "speed": 0.35, "fov": 40.0})
	_hud_show("garage")


func select_boat(id: String, color_index := 0) -> void:
	if _hull_for(id).is_empty():
		return
	selected_boat = id
	selected_color = color_index
	var prefs := SaveData.load_prefs()
	prefs["boat"] = id
	SaveData.save_prefs(prefs)
	var old := player
	var p := Race.body_pos(old)
	var boat := spawn_boat(id, p.x, p.z, Race.body_heading(old), selected_color)
	remove_boat(old)
	player = boat
	camera.follow(boat)
	_wake_attach(boat)
	_audio("click", [])


func enter_hub() -> void:
	if world_id != "hub":
		enter_world("hub")
		return
	state = "hub"
	camera.set("orbit", {})
	_hud_show("hub")
	_audio("mood", ["hub"])
	_audio("music", [true])


func _wire_hud() -> void:
	var wires := {
		"start": func(_info = null): if state == "title": show_garage() elif state == "garage": enter_hub(),
		"select_boat": func(id, color = 0): select_boat(String(id), int(color)),
		"pause": pause,
		"resume": func(): resume(false),
		"camera": func(): if camera.has_method("next_view"): camera.next_view(),
		"reset": func(): if player and player.has_method("reset"): player.reset(),
		"mute": func(m = null): if m == null: toggle_mute() else: _set_muted(bool(m)),
		"fullscreen": func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN),
		"horn": func(): _audio("horn", [selected_boat]),
		"exit": func(): resume(true); enter_world("hub"),
		"race_again": func(): if world_id != "": enter_world(world_id),
		"matte": func(): set_matte(not matte),
		"garage": func(): resume(true); await enter_world("hub"); show_garage(),
	}
	for sig in wires:
		if hud.has_signal(sig):
			hud.connect(sig, wires[sig])


func pause() -> void:
	if state == "paused" or state == "title" or state == "garage":
		return
	_paused_state = state
	state = "paused"
	get_tree().paused = true
	_hud_show("paused")
	_audio("suspend", [])


func resume(silent := false) -> void:
	if state != "paused":
		return
	state = _paused_state if _paused_state != "" else "hub"
	get_tree().paused = false
	if not silent:
		_hud_show("race" if state == "race" else "hub")
	_audio("resume", [])


## Water look: shiny (default) or matte grey topography, remembered.
func set_matte(on: bool) -> void:
	matte = on
	if ocean.has_method("set_matte"):
		ocean.set_matte(matte)
	if hud.has_method("set_matte"):
		hud.set_matte(matte)
	var prefs := SaveData.load_prefs()
	prefs["matte"] = matte
	SaveData.save_prefs(prefs)


func toggle_mute() -> void:
	_set_muted(not muted)


func _set_muted(m: bool) -> void:
	muted = m
	_audio("mute", [muted])
	if hud and hud.has_method("set_muted"):
		hud.set_muted(muted)
	var prefs := SaveData.load_prefs()
	prefs["muted"] = muted
	SaveData.save_prefs(prefs)


# ----------------------------------------------------------------- worlds
func _world_known(id: String) -> bool:
	return id == "hub" or DevCourse.has(id) or _module_worlds().has(id) or _module_sub_worlds().has(id) or not _has_worlds_module()


func _has_worlds_module() -> bool:
	return _res("res://worlds/World.gd") and _res("res://worlds/Worlds.gd")


var _worlds_cache: Dictionary = {}
var _worlds_cached := false


func _module_worlds() -> Dictionary:
	if not _worlds_cached:
		_worlds_cached = true
		if _res("res://worlds/Worlds.gd"):
			var consts: Dictionary = load("res://worlds/Worlds.gd").get_script_constant_map()
			if consts.has("WORLDS"):
				_worlds_cache = consts.WORLDS
	return _worlds_cache


## Submarine world ids: the SUB_WORLDS constant when the module exports one, else its single "deep".
func _module_sub_worlds() -> Dictionary:
	if _res("res://worlds/SubmarineWorld.gd"):
		var consts: Dictionary = load("res://worlds/SubmarineWorld.gd").get_script_constant_map()
		if consts.has("SUB_WORLDS"):
			return consts.SUB_WORLDS
		return {"deep": true}
	return {}


func load_world(id: String, immediate := true) -> void:
	_set_submerged(false)
	if world:
		if world.has_method("dispose"):
			world.dispose()
		world.queue_free()
		world = null
	portals = null
	if _module_sub_worlds().has(id):
		world = _make("res://worlds/SubmarineWorld.gd")
	elif _has_worlds_module() and _module_worlds().has(id):
		world = _make("res://worlds/World.gd")
	if world:
		_world_prep(world)
		world.build(id)
	else:
		# No worlds module (or a dev course): bare sea. Race ids get the dev loop so the flow is testable.
		var sw := StubWorld.new()
		var def := {}
		if DevCourse.has(id):
			def = DevCourse.build(id)
		elif id != "hub":
			def = DevCourse.build("devspiral" if id == "deep" else "devcourse")
			def["id"] = id
			def["name"] = id.capitalize()
		sw.build(id, def)
		world = sw
		_world_prep(world)
	world_id = id
	if "id" in world:
		world.id = id
	if "auto_update" in world:
		world.auto_update = false
	_apply_world_weather(_def(), immediate)
	for b in boats:
		b.set("ground_fn", Callable(world, "height_at"))
	# Portal rings: the world's own when it builds them, else ours for the def's portal list.
	var wp = world.get("portals")
	if wp is Node:
		portals = wp
	elif not _def().get("portals", []).is_empty():
		portals = _make("res://worlds/Portals.gd")
		if portals:
			portals.name = "Portals"
			portals.set("ocean", ocean)
			world.add_child(portals)
			portals.build(_def().get("portals", []))


func _world_prep(w: Node) -> void:
	w.name = "World"
	if "ocean" in w:
		w.ocean = ocean
	if "game" in w:
		w.game = self
	add_child(w)


func _def() -> Dictionary:
	if world == null:
		return {}
	var d = world.get("def")
	if d is Dictionary:
		return d
	return {}


func _start_of(def: Dictionary) -> Dictionary:
	var s: Dictionary = def.get("start", {})
	return {"x": float(s.get("x", 0.0)), "y": float(s.get("y", 0.0)), "has_y": s.has("y"), "z": float(s.get("z", 0.0)), "heading": float(s.get("heading", 0.0))}


## Weather: the world may apply it itself, ship ocean-contract keys, or carry the web {key, patch} shape.
func _apply_world_weather(def: Dictionary, immediate: bool) -> void:
	var w: Dictionary = {}
	if world and world.has_method("apply_weather"):
		world.apply_weather(ocean, immediate)
		return
	if _res("res://worlds/Worlds.gd") and def.has("weather") and (_module_worlds().has(world_id) or def.weather is Dictionary and def.weather.has("key")):
		var W = load("res://worlds/Worlds.gd")
		if W.has_method("apply_world_weather") and W.has_method("ocean_weather"):
			W.apply_world_weather(ocean, def, immediate)
			var ow: Dictionary = W.ocean_weather(def)
			_weather = ow
			wind.angle = deg_to_rad(float(ow.get("wind_dir_deg", 20.0)))
			wind.speed = float(ow.get("wind_speed", 5.0))
			return
	var wd = def.get("weather", null)
	if wd is Dictionary:
		if wd.has("patch") or wd.has("key"):
			w = _translate_web_weather(wd)
		else:
			w = wd.duplicate()
	if w.is_empty():
		var fallback := {
			"hub": {"wind_speed": 3.5, "wind_dir_deg": 20.0, "swell_hs": 0.35, "swell_period": 9.0, "choppiness": 1.0, "foam": 0.4, "water_color": Color(0.02, 0.28, 0.42), "sun_elev_deg": 12.0, "cloud_cover": 0.32},
			"lagoon": {"wind_speed": 4.0, "swell_hs": 0.5, "swell_period": 8.0, "foam": 0.5, "water_color": Color(0.05, 0.36, 0.36), "sun_elev_deg": 55.0, "cloud_cover": 0.14},
			"swell": {"wind_speed": 8.0, "swell_hs": 1.8, "swell_period": 12.0, "water_color": Color(0.014, 0.08, 0.14), "cloud_cover": 0.3},
			"storm": {"wind_speed": 17.0, "swell_hs": 3.0, "swell_period": 10.0, "water_color": Color(0.01, 0.05, 0.06), "cloud_cover": 0.9, "rain": 0.8, "lightning_rate": 0.2},
			"giant": {"wind_speed": 9.0, "swell_hs": 4.0, "swell_period": 16.0, "water_color": Color(0.01, 0.06, 0.13)},
			"tempest": {"wind_speed": 22.0, "swell_hs": 3.5, "swell_period": 11.0, "water_color": Color(0.014, 0.02, 0.06), "cloud_cover": 1.0, "rain": 1.0, "fog": 0.3, "lightning_rate": 0.5},
			"deep": {"wind_speed": 3.0, "swell_hs": 0.4, "swell_period": 8.0, "water_color": Color(0.01, 0.1, 0.2)},
		}
		w = fallback.get(world_id, {"wind_speed": 4.0, "swell_hs": 0.5, "swell_period": 8.0})
	_weather = w
	if ocean.has_method("set_weather"):
		ocean.set_weather(w, immediate)
	wind.angle = deg_to_rad(float(w.get("wind_dir_deg", 20.0)))
	wind.speed = float(w.get("wind_speed", 5.0))


func _translate_web_weather(wd: Dictionary) -> Dictionary:
	var p: Dictionary = wd.get("patch", {})
	var map := {"windSpeed": "wind_speed", "swellHs": "swell_hs", "swellPeriod": "swell_period", "choppiness": "choppiness",
		"foamStrength": "foam", "rain": "rain", "fog": "fog", "lightningRate": "lightning_rate", "cloudCoverage": "cloud_cover"}
	var w := {}
	for k in p:
		if map.has(k):
			w[map[k]] = p[k]
	if p.has("sunElevation"):
		w["sun_elev_deg"] = rad_to_deg(float(p.sunElevation))
	if p.has("sunAzimuth"):
		w["sun_azimuth_deg"] = rad_to_deg(float(p.sunAzimuth))
	return w


## Portal jump: white-out, rebuild the world around the origin, race or hub.
func enter_world(id: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	if _transition_portals and _transition_portals.has_method("transition"):
		await _transition_portals.transition(_do_switch.bind(id), id)
	else:
		await _fade_to(1.0, 0.35)
		_do_switch(id)
		await _fade_to(0.0, 0.5)
	_transitioning = false


func _do_switch(id: String) -> void:
	if race:
		race.dispose()
		race = null
	# Keep only the player's boat.
	for b in boats.duplicate():
		if b != player:
			remove_boat(b)
	load_world(id, true)
	var def := _def()
	var s := _start_of(def)
	# Submarine worlds swap the player's boat for a sub; surface worlds swap it back.
	var want_sub := bool(def.get("underwater", false))
	if want_sub != Race.is_sub(player):
		var old := player
		player = spawn_sub(s.x, s.y if s.has_y else 0.0, s.z, s.heading, 0) if want_sub else spawn_boat(selected_boat, s.x, s.z, s.heading, selected_color)
		remove_boat(old)
		if not want_sub:
			_wake_attach(player)
	camera.set("mode", "sub" if want_sub else "boat")
	if want_sub:
		_toast("Q dive - E rise")
	var y: float = (float(s.y) if s.has_y else _sea_h(s.x, s.z)) if want_sub else _sea_h(s.x, s.z) + 0.3
	player.set_pose(s.x, y, s.z, s.heading)
	camera.set("orbit", {})
	camera.follow(player)
	if ocean.has_method("set_focus"):
		ocean.set_focus(s.x, s.z)
	var gates: Array = def.get("gates", [])
	if not gates.is_empty():
		race = (SubRace.new() if want_sub else Race.new()).configure(self, def, {"laps": laps_override if laps_override > 0 else int(def.get("laps", 3)), "rubber_band": ai_rubber_band, "ai_count": ai_count})
		race.autopilot = autopilot
		add_child(race)
		_wire_race(race)
		race.setup()
		for b in boats:
			b.set("ground_fn", Callable(world, "height_at"))
			if b != player:
				_wake_attach(b)
		state = "race"
		_hud_show("race")
		_audio("mood", ["storm" if id == "storm" or id == "tempest" else "race"])
		_audio("music", [true])
		race.start()
	else:
		state = "hub"
		_hud_show("hub")
		_audio("mood", ["hub"])
	_audio("portal", [])


func _wire_race(r: Race) -> void:
	r.countdown_tick.connect(func(n: int): _audio("countdown", [n]))
	r.gate_passed.connect(func(boat: Node, _i: int): if boat == player: _audio("gate", []))
	r.lap.connect(func(boat: Node, _n: int): if boat == player: _audio("star", []))
	r.finished.connect(_on_player_finished)


func _on_player_finished(boat: Node, place: int, t: float) -> void:
	if boat != player:
		return
	var entry := SaveData.record_result(stars, world_id, place, t)
	if hud.has_method("set_stars"):
		hud.set_stars(stars)
	_audio("finish", [place])
	state = "results"
	_hud_show("results", {"place": place, "time": t, "stars": int(entry.stars), "best": float(entry.best), "racers": boats.size(), "world": world_id})


# ------------------------------------------------------------------ boats
func _hull_for(id: String) -> Dictionary:
	if _res("res://boats/Hulls.gd"):
		var consts: Dictionary = load("res://boats/Hulls.gd").get_script_constant_map()
		var hulls: Dictionary = consts.get("HULLS", {})
		if hulls.has(id):
			return hulls[id]
	if StubHulls.HULLS.has(id):
		return StubHulls.HULLS[id]
	return {}


## Create a boat: physics body (real BoatPhysics or StubBoat) + visual, placed on the water.
func spawn_boat(id: String, x: float, z: float, heading := 0.0, color_index := 0) -> Node:
	var hull := _hull_for(id)
	if hull.is_empty():
		hull = _hull_for("speedboat")
	var body: Node3D
	var ground := Callable(world, "height_at") if world else Callable()
	var real_boat := _make("res://boats/Boat.tscn")
	if real_boat == null:
		real_boat = _make("res://boats/BoatPhysics.gd")
	if real_boat is Node3D:
		body = real_boat
		if body.has_method("configure"):
			body.configure(id, color_index, ocean, ground)   # BoatPhysics.configure(id, color, ocean, ground)
		else:
			body.set("hull", hull)
			body.set("ocean", ocean)
		var hb = body.get("hull")
		if hb is Dictionary and not hb.is_empty():
			hull = hb
		# Main steps every body in update() (web order: boats, collisions, race, camera).
		body.set("simulate", false)
		body.set("auto_update", false)
		_has["boats"] = true
	else:
		var sb := StubBoat.new()
		sb.configure(id, hull, ocean, color_index)
		body = sb
	body.name = "%s%d" % [id.capitalize(), boats.size()]
	body.set_meta("boat_id", id)
	body.set_meta("label", String(hull.get("label", id)))
	body.set_meta("color_index", color_index)
	body.set("ground_fn", ground)
	_boats_node.add_child(body)
	if _res("res://boats/Boats.gd") and body.get_node_or_null("Visual") == null and not bool(body.get("auto_visual")):
		var visual = load("res://boats/Boats.gd").build_visual(id, color_index)
		if visual is Node3D:
			visual.name = "Visual"
			body.add_child(visual)
	body.set_pose(x, _sea_h(x, z) + 0.3, z, heading)
	boats.append(body)
	return body


## Create a submarine (player or AI) at a 3D position.
func spawn_sub(x: float, y: float, z: float, heading := 0.0, color_index := 0) -> Node:
	var body: Node3D
	var real_sub := _make("res://boats/Submarine.tscn")
	if real_sub == null:
		real_sub = _make("res://boats/SubPhysics.gd")
	if real_sub is Node3D:
		body = real_sub
		if "ocean" in body:
			body.ocean = ocean
		if "ceiling_fn" in body:
			body.ceiling_fn = Callable(ocean, "height_at")
		body.set("simulate", false)
		body.set("auto_update", false)
		var vis: Node = body.get_node_or_null("Visual")
		if vis and "color_index" in vis:
			vis.color_index = color_index
		_has["sub"] = true
	else:
		var ss := StubSub.new()
		ss.configure(ocean, color_index)
		body = ss
	body.name = "Sub%d" % boats.size()
	body.set_meta("boat_id", "sub")
	if not body.has_meta("label"):
		body.set_meta("label", "Submarine")
	body.set_meta("color_index", color_index)
	if world:
		body.set("ground_fn", Callable(world, "height_at"))
	_boats_node.add_child(body)
	if _res("res://boats/Boats.gd") and body.get_node_or_null("Visual") == null and body.get_child_count() == 0:
		var visual = load("res://boats/Boats.gd").build_visual("sub", color_index)
		if visual is Node3D:
			visual.name = "Visual"
			body.add_child(visual)
	body.set_pose(x, y, z, heading)
	boats.append(body)
	return body


func remove_boat(boat: Node) -> void:
	if boat == null:
		return
	boats.erase(boat)
	if is_instance_valid(boat):
		boat.queue_free()


## Step one body: BoatPhysics.advance(dt) (simulate off), SubPhysics.update(dt) (auto_update off),
## or a stub's update(dt, wind). The sailboat reads `wind` if the body exposes it.
func _step_body(b: Node, dt: float) -> void:
	if "wind" in b:
		b.wind = wind
	if b.has_method("advance"):
		b.advance(dt)
	elif b.has_method("update"):
		if "auto_update" in b:
			b.update(dt)
		else:
			b.update(dt, wind)


## Wake: one boats/Wake.gd node per hull (it reads body.sea_hs(), so only real BoatPhysics bodies).
func _wake_attach(boat: Node) -> void:
	if not _has.get("wake", false) or boat == null or not boat.has_method("sea_hs"):
		return
	if boat.get_node_or_null("Wake"):
		return
	var w := _make("res://boats/Wake.gd")
	if w:
		w.name = "Wake"
		w.set("body", boat)
		boat.add_child(w)


func _set_submerged(on: bool) -> void:
	if _submerged == on:
		return
	_submerged = on
	if world and world.has_method("set_submerged"):
		var cp := camera.global_position
		world.set_submerged(on, maxf(0.0, _sea_h(cp.x, cp.z) - cp.y), camera)
		return
	if _env == null:
		return
	# Fallback underwater look: dense blue fog.
	if on:
		_env_saved = {"fog": _env.fog_enabled, "col": _env.fog_light_color, "den": _env.fog_density, "bg": _env.background_mode, "bgc": _env.background_color}
		_env.fog_enabled = true
		_env.fog_light_color = Color(0.02, 0.18, 0.3)
		_env.fog_density = 0.035
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.01, 0.12, 0.22)
	elif not _env_saved.is_empty():
		_env.fog_enabled = _env_saved.fog
		_env.fog_light_color = _env_saved.col
		_env.fog_density = _env_saved.den
		_env.background_mode = _env_saved.bg
		_env.background_color = _env_saved.bgc


# ------------------------------------------------------------------- loop
var driving: bool:
	get:
		return state == "hub" or state == "race" or state == "results"


func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	_read_controls(dt)
	if _action("pause"):
		if state == "paused":
			resume()
		else:
			pause()
	if get_tree().paused or state == "paused":
		return
	update(dt)


func update(dt: float) -> void:
	time += dt
	if player and ocean.has_method("set_focus"):
		var pp := Race.body_pos(player)
		ocean.set_focus(pp.x, pp.z)

	if _action("mute"):
		toggle_mute()
	if (state == "title" or state == "garage") and (_ctrl.enter or _action("confirm") or Input.is_action_just_pressed("throttle")):
		if state == "title":
			show_garage()
		else:
			enter_hub()

	if player:
		var can_drive: bool = driving and (race == null or race.accepts_input)
		if race and race.autopilot and race.state != "setup":
			pass   # Race drives the player's body
		elif can_drive:
			player.set("throttle", _ctrl.throttle)
			player.set("steer", _ctrl.steer)
			player.set("boost", 1.0 if _ctrl.boost else 0.0)
			if Race.is_sub(player):
				player.set("dive", _ctrl.dive)
		else:
			player.set("throttle", 0.0)
			player.set("steer", 0.0)
			player.set("boost", 0.0)
			if Race.is_sub(player):
				player.set("dive", 0.0)
		if _action("reset") and player.has_method("reset"):
			player.reset()
		if _action("camera") and camera.has_method("next_view"):
			camera.next_view()
		if _action("horn"):
			_audio("horn", [selected_boat])

	# Boats: step, soft bounds, beached rescue, slap feedback.
	var bounds := float(_def().get("bounds", 900.0))
	for boat in boats:
		var before := float(boat.get("slap_impulse")) if boat.get("slap_impulse") != null else 0.0
		_step_body(boat, dt)
		var p := Race.body_pos(boat)
		var r := Vector2(p.x, p.z).length()
		if r > bounds and "velocity" in boat:
			boat.velocity += Vector3(-p.x / r, 0, -p.z / r) * (dt * 6.0 * minf(3.0, (r - bounds) / 40.0))
		var bt = boat.get("beached_time")
		if bt != null and float(bt) > 1.5 and boat.has_method("rescue"):
			boat.rescue()
			if boat == player:
				_toast("Back to the water!")
		var si = boat.get("slap_impulse")
		if si != null and float(si) > before + 0.2:
			if boat == player and camera.has_method("impulse"):
				camera.impulse(float(si) * 0.6)
			_audio("splash", [float(si)])

	_collide_boats(dt)
	if race:
		race.update(dt)
	if world and world.has_method("update"):
		if "underwater" in world:
			world.update(dt, camera)   # SubmarineWorld.update(dt, camera)
		else:
			world.update(dt)
	if world and _module_worlds().has(world_id):
		var W = load("res://worlds/Worlds.gd")
		if W and W.has_method("update_world_events"):
			W.update_world_events(ocean, _def(), dt, Race.body_pos(player) if player else Vector3.INF)
	if world and (bool(_def().get("underwater", false)) or ("underwater" in world and bool(world.underwater))):
		var cp := camera.global_position
		var depth := _sea_h(cp.x, cp.z) - cp.y
		var was := _submerged
		_set_submerged(depth > 0.3)
		if _submerged and was and world.has_method("set_submerged"):
			world.set_submerged(true, depth, camera)   # per-frame depth tint
	if portals and portals.has_method("update") and portals.get_parent() != world:
		portals.update(dt)   # ours; a world-built Portals is ticked by world.update()
	if portals and portals.has_method("test") and driving and player and not _transitioning:
		var dest = portals.test(player)
		if dest is String and dest != "":
			enter_world(dest)
	if camera.has_method("update"):
		camera.update(dt)

	# Audio
	if audio and audio.has_method("set_engine") and player:
		var b := player
		var thr := float(b.get("throttle")) if b.get("throttle") != null else 0.0
		var ms := Race.hull_num(b, "max_speed", 20.0)
		var sp := Race.body_speed(b)
		var subm := float(b.get("submersion")) if b.get("submersion") != null else 1.0
		audio.set_engine(selected_boat if not Race.is_sub(b) else "sub", clampf(absf(thr) * 0.7 + sp / ms * 0.5, 0.0, 1.0), maxf(0.0, thr), sp / ms, subm)

	# HUD
	if player:
		var f := _frame
		var b := player
		f["speed_kmh"] = Race.body_speed(b) * 3.6
		f["state"] = state
		f["world"] = world_id
		var pl: Dictionary = race.player if race else {}
		f["lap"] = int(pl.get("lap", 0))
		f["laps"] = race.laps if race else 0
		f["position"] = int(pl.get("position", 0))
		f["racers"] = boats.size() if race else 0
		f["time"] = race.time if race else 0.0
		f["countdown"] = race.countdown if race else 0.0
		f["next_gate_dir"] = race.next_gate_dir() if race else 0.0
		f["progress"] = float(pl.get("progress", 0.0))
		f["finished"] = bool(pl.get("finished", false))
		f["submerged"] = Race.is_sub(b)
		f["depth"] = maxf(0.0, float(b.get("depth"))) if (Race.is_sub(b) and b.get("depth") != null) else 0.0
		f["next_gate_pitch"] = race.next_gate_pitch() if (race and race.has_method("next_gate_pitch")) else 0.0
		f["stars"] = SaveData.total_stars(stars)
		var best := float(stars.get(world_id, {}).get("best", 0.0))
		f["best_time"] = best if is_finite(best) else 0.0
		if hud.has_method("update"):
			hud.update(f)


## Boat-vs-boat contact: each hull is two spheres along its length (radius = half the beam).
## Overlapping pairs are pushed apart mass-weighted, exchange a little normal velocity and get a
## yaw kick, so boats bump and slide off each other instead of passing through.
func _collide_boats(_dt: float) -> void:
	# (dt is used for the separation impulse below)
	var n := boats.size()
	if n < 2:
		return
	for i in n:
		var A: Node3D = boats[i]
		var ra := maxf(0.6, Race.hull_num(A, "width", 2.0) * 0.5)
		var la := Race.hull_num(A, "length", 6.0) * 0.25
		var ma := Race.hull_num(A, "mass", 1000.0)
		var fa := Race.body_fwd(A)
		for j in range(i + 1, n):
			var B: Node3D = boats[j]
			var rb := maxf(0.6, Race.hull_num(B, "width", 2.0) * 0.5)
			var lb := Race.hull_num(B, "length", 6.0) * 0.25
			var mb := Race.hull_num(B, "mass", 1000.0)
			var fb := Race.body_fwd(B)
			var reach := la * 2 + lb * 2 + ra + rb
			if A.global_position.distance_squared_to(B.global_position) > reach * reach:
				continue
			for sa in [-1.0, 1.0]:
				var ca: Vector3 = A.global_position + fa * (sa * la)
				for sb in [-1.0, 1.0]:
					var cb: Vector3 = B.global_position + fb * (sb * lb)
					var cn := cb - ca
					var d := cn.length()
					var min_d := ra + rb
					if d >= min_d or d < 1e-4:
						continue
					cn /= d
					var pen := min_d - d
					var wa := mb / (ma + mb)
					var wb := ma / (ma + mb)
					# Separation as a one-frame velocity correction: the physics bodies own their transforms.
					var sep := minf(pen * 0.5 / maxf(_dt, 1e-3), 6.0)
					var va := Race.body_vel(A) - cn * (sep * wa)
					var vb := Race.body_vel(B) + cn * (sep * wb)
					A.set("velocity", va)
					B.set("velocity", vb)
					var vn := (vb - va).dot(cn)
					if vn < 0.0:
						var jn := -(1.0 + 0.35) * vn / (1.0 / ma + 1.0 / mb)
						A.set("velocity", va + cn * (-jn / ma))
						B.set("velocity", vb + cn * (jn / mb))
						var bump := minf(1.0, -vn / 6.0)
						if "angular" in A:
							var aa: Vector3 = A.angular
							aa.y += sa * bump * 0.35 * (1.0 if cn.dot(Race.body_lat(A)) > 0.0 else -1.0)
							A.angular = aa
						if "angular" in B:
							var ab: Vector3 = B.angular
							ab.y += sb * bump * 0.35 * (-1.0 if cn.dot(Race.body_lat(B)) > 0.0 else 1.0)
							B.angular = ab
						if bump > 0.15 and (A == player or B == player):
							if camera.has_method("impulse"):
								camera.impulse(bump * 0.5)
							_audio("splash", [bump])


# ---------------------------------------------------------------- controls
## Read the Controls autoload when present, else the input map directly (web Controls.js smoothing).
func _read_controls(dt: float) -> void:
	var c := _ctrl
	c.actions = {}
	c.enter = false
	if controls:
		c.throttle = float(controls.get("throttle")) if controls.get("throttle") != null else 0.0
		c.steer = float(controls.get("steer")) if controls.get("steer") != null else 0.0
		c.boost = bool(controls.get("boost"))
		c.dive = float(controls.get("dive")) if controls.get("dive") != null else 0.0
		for a in ["pause", "camera", "reset", "horn", "mute", "confirm"]:
			var hit := false
			if controls.has_method("has"):
				hit = bool(controls.has(a))
			else:
				var acts = controls.get("actions")
				hit = (acts is Array and acts.has(a)) or (acts is Dictionary and acts.has(a))
			if hit:
				c.actions[a] = true
		c.enter = c.actions.has("confirm")
		return
	var thr := Input.get_action_strength("throttle")
	var brake := Input.get_action_strength("brake")
	var steer := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var dive := Input.get_action_strength("dive_up") - Input.get_action_strength("dive_down")
	var any := thr > 0.0 or brake > 0.0 or steer != 0.0 or dive != 0.0
	var out := clampf(thr - brake * (1.0 if thr > 0.0 else 0.5), -0.5, 1.0)
	var sk := 1.0 - exp(-dt * (10.0 if any else 6.0))
	var ss := float(c.get("steer_s", 0.0)) + (clampf(steer, -1, 1) - float(c.get("steer_s", 0.0))) * sk
	var ts := float(c.get("thr_s", 0.0)) + (out - float(c.get("thr_s", 0.0))) * (1.0 - exp(-dt * 4.0))
	var ds := float(c.get("dive_s", 0.0)) + (clampf(dive, -1, 1) - float(c.get("dive_s", 0.0))) * (1.0 - exp(-dt * 6.0))
	c.steer_s = ss
	c.thr_s = ts
	c.dive_s = ds
	c.steer = 0.0 if absf(ss) < 0.005 else ss
	c.throttle = 0.0 if absf(ts) < 0.005 else ts
	c.dive = 0.0 if absf(ds) < 0.005 else ds
	c.boost = Input.is_action_pressed("boost")
	# Rising edges tracked here (not is_action_just_pressed): the harness presses actions from a
	# post-draw callback, which the per-frame "just pressed" stamp misses.
	for a in [["pause", "pause"], ["camera", "camera"], ["reset", "reset_boat"], ["horn", "horn"]]:
		var down := Input.is_action_pressed(a[1])
		if down and not bool(c.get("down_" + a[0], false)):
			c.actions[a[0]] = true
		c["down_" + a[0]] = down
	if Input.is_key_pressed(KEY_M) and not bool(c.get("m_down", false)):
		c.actions["mute"] = true
	c.m_down = Input.is_key_pressed(KEY_M)
	var enter_now := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	c.enter = enter_now and not bool(c.get("enter_down", false))
	c.enter_down = enter_now


func _action(a: String) -> bool:
	return _ctrl.actions.has(a)


# ------------------------------------------------------------ helpers
func _hud_show(screen: String, data: Dictionary = {}) -> void:
	if hud == null:
		return
	if hud.has_method("show_screen"):
		hud.show_screen(screen, data)
	elif hud.has_method("show") and not (hud is CanvasItem or hud is CanvasLayer):
		hud.call("show", screen, data)


func _sea_h(x: float, z: float) -> float:
	return float(ocean.height_at(x, z)) if ocean and ocean.has_method("height_at") else 0.0


func _toast(text: String) -> void:
	if hud and hud.has_method("toast"):
		hud.toast(text)


func _audio(method: String, args: Array) -> void:
	if audio and audio.has_method(method):
		audio.callv(method, args)


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Fade"
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	add_child(layer)


func _fade_to(alpha: float, seconds: float) -> void:
	var from := _fade.color.a
	var t := 0.0
	while t < seconds:
		var d := get_process_delta_time()
		t += d
		_fade.color.a = lerpf(from, alpha, clampf(t / seconds, 0, 1))
		await get_tree().process_frame
	_fade.color.a = alpha


## Diagnostics for tools/godot-run.mjs (group harness_state).
func get_harness_state() -> Dictionary:
	var st := {"state": state, "world": world_id, "boat": selected_boat, "boats": boats.size(), "modules": _has.keys()}
	if player and is_instance_valid(player):
		var p := Race.body_pos(player)
		st["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		st["speed_kmh"] = snappedf(Race.body_speed(player) * 3.6, 0.1)
		st["heading"] = snappedf(Race.body_heading(player), 0.001)
		st["sea"] = snappedf(_sea_h(p.x, p.z), 0.01)
	if race:
		var pl := race.player
		var standings := []
		for s in race.standings:
			standings.append({"name": s.name, "pos": s.position, "lap": s.lap, "gate": s.gate, "gates": s.gates_total, "kmh": snappedf(s.speed_kmh, 0.1), "stuck": s.stuck_nudges, "ai": s.ai, "done": s.finished})
		st["race"] = {"state": race.state, "lap": pl.get("lap", 0), "gate": pl.get("next_gate", 0), "position": pl.get("position", 0),
			"time": snappedf(race.time, 0.1), "countdown": snappedf(race.countdown, 0.1), "standings": standings}
	return st
