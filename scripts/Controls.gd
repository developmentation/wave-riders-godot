extends Node
## Unified input (autoload "Controls") — port of src/game/Controls.js.
## Keyboard/gamepad via the input map actions (throttle, brake, steer_left,
## steer_right, boost, dive_down, dive_up, reset_boat, camera, pause, horn),
## raw gamepad triggers/buttons, and whatever the touch HUD writes into
## `virtual`. Output is a normalised, smoothed intent so the boat physics never
## knows about devices. +steer = right (bow to the boat's visual right).

## -0.5 .. 1 (negative = reverse)
var throttle := 0.0
## -1 .. 1 (positive = right)
var steer := 0.0
var brake := 0.0
var boost := false
## -1..1, +up (submarine mode)
var dive := 0.0
## true while any drive input is active this frame
var active := false
## One-frame events, as Dictionary keys: "reset", "camera", "pause", "horn", "confirm", "mute".
var actions: Dictionary = {}
## Written by the HUD's touch controls every frame it is active:
## {steer, throttle, brake, boost, dive, active}
var virtual := {"throttle": 0.0, "steer": 0.0, "brake": 0.0, "boost": false, "dive": 0.0, "active": false}
## Device-orientation steering, -1..1 (set_tilt / clear_tilt).
var tilt_enabled := false
var tilt_value := 0.0
var last_device := "keyboard"

var _steer_smooth := 0.0
var _throttle_smooth := 0.0
var _dive_smooth := 0.0
var _pending: Dictionary = {}
var _prev: Dictionary = {}


func _ready() -> void:
	process_priority = -100   # before every consumer's _process


## Touch HUD writes here every frame it is active.
func set_virtual(v: Dictionary) -> void:
	for k in v.keys():
		virtual[k] = v[k]


func set_tilt(value: float) -> void:
	tilt_value = value
	tilt_enabled = true


func clear_tilt() -> void:
	tilt_enabled = false


## Queue a one-frame action (HUD buttons call this).
func trigger(action: String) -> void:
	_pending[action] = true


func has(action: String) -> bool:
	return actions.has(action)


func _edge(key: String, pressed: bool, action: String) -> void:
	if pressed and not _prev.get(key, false):
		_pending[action] = true
	_prev[key] = pressed


func _process(dt: float) -> void:
	var thr := 0.0
	var st := 0.0
	var brk := 0.0
	var bst := false
	var dv := 0.0
	var any := false

	# keyboard (and anything else bound in the input map, incl. joypad stick/A)
	var a_thr := Input.get_action_strength("throttle")
	var a_brk := Input.get_action_strength("brake")
	var a_l := Input.get_action_strength("steer_left")
	var a_r := Input.get_action_strength("steer_right")
	if a_thr > 0.0:
		thr += a_thr
		any = true
	if a_brk > 0.0:
		brk = a_brk
		any = true
	if a_l > 0.0 or a_r > 0.0:
		st += a_r - a_l
		any = true
	if Input.is_action_pressed("boost"):
		bst = true
	var d_down := Input.get_action_strength("dive_down")
	var d_up := Input.get_action_strength("dive_up")
	if d_down > 0.0 or d_up > 0.0:
		dv += d_up - d_down
		any = true
	if any:
		last_device = "keyboard"
	for pair in [["reset_boat", "reset"], ["camera", "camera"], ["pause", "pause"], ["horn", "horn"]]:
		if Input.is_action_just_pressed(pair[0]):
			_pending[pair[1]] = true
	_edge("enter", Input.is_key_pressed(KEY_ENTER), "confirm")
	_edge("m", Input.is_key_pressed(KEY_M), "mute")

	# gamepad: triggers, face buttons, bumpers (left stick / A are in the input map)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var gp: int = pads[0]
		var rt := Input.get_joy_axis(gp, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(gp, JOY_AXIS_TRIGGER_LEFT)
		rt = 0.0 if rt < 0.12 else rt
		lt = 0.0 if lt < 0.12 else lt
		if rt > 0.0 or lt > 0.0:
			any = true
			last_device = "gamepad"
		thr += rt
		brk = maxf(brk, lt)
		if Input.is_joy_button_pressed(gp, JOY_BUTTON_B):
			bst = true
		if Input.is_joy_button_pressed(gp, JOY_BUTTON_LEFT_SHOULDER):
			dv -= 1.0   # LB down
		if Input.is_joy_button_pressed(gp, JOY_BUTTON_RIGHT_SHOULDER):
			dv += 1.0   # RB up
		_edge("gp_y", Input.is_joy_button_pressed(gp, JOY_BUTTON_Y), "reset")
		_edge("gp_x", Input.is_joy_button_pressed(gp, JOY_BUTTON_X), "camera")
		_edge("gp_start", Input.is_joy_button_pressed(gp, JOY_BUTTON_START), "pause")

	# touch HUD
	if virtual.get("active", false):
		last_device = "touch"
		thr += float(virtual.get("throttle", 0.0))
		brk = maxf(brk, float(virtual.get("brake", 0.0)))
		st += float(virtual.get("steer", 0.0))
		bst = bst or bool(virtual.get("boost", false))
		dv += float(virtual.get("dive", 0.0))
		any = true
	if tilt_enabled:
		st += tilt_value

	st = clampf(st, -1.0, 1.0)
	thr = clampf(thr, 0.0, 1.0)
	# Brake: slows, and once nearly stopped becomes reverse.
	var out := thr - brk * (1.0 if thr > 0.0 else 0.5)
	out = clampf(out, -0.5, 1.0)

	# Smooth like a real helm and throttle lever: quick to respond, not instant.
	var sk := 1.0 - exp(-dt * (10.0 if any else 6.0))
	_steer_smooth += (st - _steer_smooth) * sk
	var tk := 1.0 - exp(-dt * 4.0)
	_throttle_smooth += (out - _throttle_smooth) * tk
	steer = 0.0 if absf(_steer_smooth) < 0.005 else _steer_smooth
	throttle = 0.0 if absf(_throttle_smooth) < 0.005 else _throttle_smooth
	brake = brk
	boost = bst
	var dk := 1.0 - exp(-dt * 6.0)
	_dive_smooth += (clampf(dv, -1.0, 1.0) - _dive_smooth) * dk
	dive = 0.0 if absf(_dive_smooth) < 0.005 else _dive_smooth
	active = any

	actions = _pending
	_pending = {}
