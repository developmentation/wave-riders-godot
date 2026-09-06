extends Node
## Wave Riders — procedural audio (port of src/game/Audio.js). Autoload "GameAudio".
##
## Everything is synthesized into one AudioStreamGenerator (24 kHz, mono → stereo) from
## precomputed wavetables; no audio files. `_process` renders 256-sample blocks whenever the
## generator has room, so CPU cost is a fraction of a millisecond per frame. Signal flow mirrors
## the web build: engine + spray → engineBus, one-shots → sfxBus, wind/rain → ambientBus,
## music → musicGain, all → master (volume, mute) → soft limiter → output.
##
##   GameAudio.set_engine("speedboat", rpm, load, speed_frac, submersion)   # every frame
##   GameAudio.gate() / wrong_gate() / portal() / countdown(n) / finish(place) / horn(type)
##   GameAudio.star() / click() / splash(i) / lightning(distance_m) / rain(level) / wind(level)
##   GameAudio.music(true) ; GameAudio.mood("hub" | "race" | "storm") ; mute(b) ; set_volume(v)
## Tuned for small ears in a shared room: moderate engine, quiet music, nothing shrill.

const RATE := 24000
const BLOCK := 256
const TBL := 2048
const TBL_MASK := 2047
const NOISE_LEN := 65536
const NOISE_MASK := 65535
const MAX_VOICES := 40

const BUS_ENGINE := 0.5
const BUS_SFX := 0.7
const BUS_AMBIENT := 0.5
const BUS_MUSIC := 0.16

const MOODS := {
	"hub": {"bpm": 112.0, "root": 261.63, "minor": false, "cutoff": 2400.0, "kicks": [0, 2], "arp_gain": 1.0},
	"race": {"bpm": 128.0, "root": 293.66, "minor": false, "cutoff": 3800.0, "kicks": [0, 1, 2, 3], "arp_gain": 1.0},
	"storm": {"bpm": 100.0, "root": 220.0, "minor": true, "cutoff": 1300.0, "kicks": [0, 2], "arp_gain": 0.8},
}
const PROG_MAJOR := [[0, 4, 7, 9], [9, 12, 16, 19], [2, 4, 7, 9], [7, 9, 14, 16]]
const PROG_MINOR := [[0, 3, 7, 10], [3, 7, 10, 15], [5, 7, 10, 12], [7, 10, 14, 15]]
const ARP_A := [0, 1, 2, 3, 2, 1, 0, 2]
const ARP_B := [0, 2, 1, 3, 1, 2, 3, 1]
const ENGINE_TYPES := {
	"jetski": "jetski", "airboat": "jetski", "speedboat": "speedboat", "towboat": "speedboat",
	"pontoon": "pontoon", "fishing": "pontoon", "tug": "pontoon", "sailboat": "sailboat", "rowboat": "sailboat", "sub": "sub",
}

var ready_ := false
var muted := false
var volume := 0.8
var mood_name := "hub"

var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _blk: PackedVector2Array
var _acc: PackedFloat32Array
var _eng: PackedFloat32Array
var _tables: Dictionary = {}
var _noise: PackedFloat32Array
var _crackle: PackedFloat32Array
var _voices: Array = []
var _t_samples := 0
var _master := 0.8
var _lim_gain := 1.0
var _paused := false
var _capture: AudioEffectCapture
var _max_blocks_per_frame := 24

# engine rig
var _engine_type := ""
var _eng_osc: Array = []          # [{tbl, phase, inc, inc_t, gain, gain_t, tc_inc, tc_gain}]
var _eng_lp := _Biquad.new()
var _eng_lp_f := 800.0
var _eng_lp_f_t := 800.0
var _eng_amp := 0.0
var _eng_amp_t := 0.0
var _eng_load_prev := 0.0
var _eng_next_flap := 0
var _eng_last_call := 0
var _crackle_v := _NoiseVoice.new()
var _crackle_env := 0.0
var _sail_v := _NoiseVoice.new()
var _spray := _NoiseVoice.new()
var _wind := _NoiseVoice.new()
var _rain := _NoiseVoice.new()
var _rain_level := 0.0
var _wind_level := 0.0
var _wind_lfo := 0.0
var _sub_trem := 0.0
var _last_splash := -100000

# music
var _music_on := false
var _music_gain := 0.0
var _music_gain_t := 0.0
var _m_step := 0
var _m_next := 0


# =========================================================================== lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_tables()
	_blk = PackedVector2Array()
	_blk.resize(BLOCK)
	_acc = PackedFloat32Array()
	_acc.resize(BLOCK)
	_eng = PackedFloat32Array()
	_eng.resize(BLOCK)
	for i in MAX_VOICES:
		_voices.append(_Voice.new())
	_spray.set_filter(2, 1800.0, 0.7)
	_wind.set_filter(2, 380.0, 1.1)
	_rain.set_filter(2, 1600.0, 0.32)
	_sail_v.set_filter(2, 300.0, 0.6)
	_crackle_v.set_filter(2, 1400.0, 2.5)
	_crackle_v.table = _crackle
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.name = "Synth"
	_player.stream = gen
	_player.bus = "Master"
	add_child(_player)
	unlock()


## Web parity: start the output. Safe to call any time.
func unlock() -> void:
	if not _player.playing:
		_player.play()
	_pb = _player.get_stream_playback()
	ready_ = _pb != null
	_master = 0.0 if muted else volume


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_paused = true
	elif what == NOTIFICATION_UNPAUSED:
		_paused = false
	elif what == NOTIFICATION_EXIT_TREE:
		# Release the playback ref before the player is freed (otherwise it leaks at exit).
		ready_ = false
		_pb = null
		if _player != null:
			_player.stop()
		if _capture != null:
			for i in AudioServer.get_bus_effect_count(0):
				if AudioServer.get_bus_effect(0, i) == _capture:
					AudioServer.remove_bus_effect(0, i)
					break
			_capture = null


func mute(on: bool) -> void:
	muted = on


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


# ============================================================================ tables
static func _additive(partials: int, kind: String) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TBL)
	var peak := 0.0
	for i in TBL:
		var x := float(i) / float(TBL)
		var s := 0.0
		match kind:
			"saw":
				for n in range(1, partials + 1):
					s += sin(TAU * n * x) / float(n)
				s *= -2.0 / PI
			"square":
				var n := 1
				while n <= partials:
					s += sin(TAU * n * x) / float(n)
					n += 2
				s *= 4.0 / PI
			"tri":
				var n := 1
				var sign := 1.0
				while n <= partials:
					s += sign * sin(TAU * n * x) / float(n * n)
					sign = -sign
					n += 2
				s *= 8.0 / (PI * PI)
			_:
				s = sin(TAU * x)
		t[i] = s
		peak = maxf(peak, absf(s))
	if peak > 0.0:
		for i in TBL:
			t[i] /= peak
	return t


func _build_tables() -> void:
	_tables["sine"] = _additive(1, "sine")
	_tables["tri"] = _additive(15, "tri")
	_tables["tri6"] = _additive(5, "tri")
	_tables["saw"] = _additive(40, "saw")
	_tables["saw12"] = _additive(12, "saw")
	_tables["saw5"] = _additive(5, "saw")
	_tables["square"] = _additive(39, "square")
	_tables["square11"] = _additive(11, "square")
	_tables["square5"] = _additive(5, "square")
	var saw: PackedFloat32Array = _tables["saw"]
	var sq: PackedFloat32Array = _tables["square"]
	var tri: PackedFloat32Array = _tables["tri"]
	# Jet ski: 2-stroke buzz — saw at the fundamental + square an octave up.
	var jet := PackedFloat32Array()
	jet.resize(TBL)
	for i in TBL:
		jet[i] = (saw[i] * 0.66 + sq[(i * 2) & TBL_MASK] * 0.34) * 0.9
	_tables["jetski"] = jet
	# Speedboat V8: the table spans TWO firing cycles so the half-rate amplitude chug bakes in:
	# saw(f) * (1 + 0.12 square(f/2)) + 0.1 triangle(2f).
	var v8 := PackedFloat32Array()
	v8.resize(TBL)
	for i in TBL:
		var am := 1.0 + 0.12 * sq[i]
		v8[i] = (saw[(i * 2) & TBL_MASK] * am + 0.14 * tri[(i * 4) & TBL_MASK]) * 0.8
	_tables["speedboat"] = v8
	# Pontoon outboard putter: saw + square with a per-firing chug.
	var put := PackedFloat32Array()
	put.resize(TBL)
	for i in TBL:
		put[i] = (saw[i] * 0.66 + sq[i] * 0.34) * (1.0 + 0.2 * sq[i]) * 0.75
	_tables["pontoon"] = put
	# Submarine hum: warm sine stack.
	var hum := PackedFloat32Array()
	hum.resize(TBL)
	for i in TBL:
		var x := TAU * float(i) / float(TBL)
		hum[i] = (sin(x) + 0.35 * sin(2.0 * x) + 0.12 * sin(3.0 * x)) / 1.47
	_tables["sub"] = hum
	# Shared white noise + a 17 Hz pulsed copy for exhaust crackle.
	_noise = PackedFloat32Array()
	_noise.resize(NOISE_LEN)
	_crackle = PackedFloat32Array()
	_crackle.resize(NOISE_LEN)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var pulse_len := int(RATE / 17.0)
	for i in NOISE_LEN:
		var v := rng.randf_range(-1.0, 1.0)
		_noise[i] = v
		_crackle[i] = v if (i % pulse_len) < pulse_len / 2 else 0.0
	_spray.table = _noise
	_wind.table = _noise
	_rain.table = _noise
	_sail_v.table = _noise


func _table_for(kind: String, f: float) -> PackedFloat32Array:
	match kind:
		"sawtooth", "saw":
			return _tables["saw"] if f < 180.0 else (_tables["saw12"] if f < 700.0 else _tables["saw5"])
		"square":
			return _tables["square"] if f < 180.0 else (_tables["square11"] if f < 700.0 else _tables["square5"])
		"triangle", "tri":
			return _tables["tri"] if f < 900.0 else _tables["tri6"]
		_:
			return _tables["sine"]


# ============================================================================= mixing
func _process(_dt: float) -> void:
	if not ready_:
		return
	var target_master := 0.0 if muted else volume
	_master += (target_master - _master) * 0.2
	var avail := _pb.get_frames_available()
	var blocks := mini(avail / BLOCK, _max_blocks_per_frame)
	for b in blocks:
		_render_block()
		_pb.push_buffer(_blk)


func _render_block() -> void:
	var acc := _acc
	var n := BLOCK
	acc.fill(0.0)
	_render_engine(acc, n)
	_render_ambient(acc, n)
	_render_music(acc, n)
	for v in _voices:
		if v.active:
			v.render(acc, n)
	# master + soft limiter (peak follower per block, fast attack / slow release)
	var peak := 0.0
	for i in n:
		var a := absf(acc[i])
		if a > peak:
			peak = a
	var g := _master
	var want := 1.0
	if peak * g > 0.85:
		want = 0.85 / (peak * g)
	if want < _lim_gain:
		_lim_gain = want
	else:
		_lim_gain = minf(1.0, _lim_gain * 1.02 + 0.0005)
	var gg := g * _lim_gain
	var blk := _blk
	for i in n:
		var s := acc[i] * gg
		if s > 0.95:
			s = 0.95 + (s - 0.95) * 0.1
		elif s < -0.95:
			s = -0.95 + (s + 0.95) * 0.1
		blk[i] = Vector2(s, s)
	_t_samples += n


# ============================================================================= engine
## Continuous engine + spray; call every frame. type: boat id (jetski speedboat sailboat pontoon
## fishing tug airboat towboat rowboat sub). rpm 0..1.2, load 0..1 (|throttle|), speed 0..1 as a
## fraction of the hull's top speed, submersion 0..1 (1 = hull in the water).
func set_engine(type: String, rpm: float, load: float, speed: float, submersion := 1.0, airborne := false) -> void:
	if not ready_:
		return
	var etype: String = ENGINE_TYPES.get(type, "sailboat")
	if etype != _engine_type:
		_build_engine(etype)
	_eng_last_call = _t_samples
	rpm = clampf(rpm, 0.0, 1.2)
	load = clampf(load, 0.0, 1.0)
	var spd := clampf(speed, 0.0, 1.2)
	var sub := clampf(submersion, 0.0, 1.0)
	var air_k := 1.15 if airborne else 1.0
	var duck := 0.0 if _paused else 1.0
	match etype:
		"jetski":
			var f := 95.0 + 215.0 * rpm
			if type == "airboat":
				f = 120.0 + 260.0 * rpm
			_eng_osc[0]["inc_t"] = f * TBL / RATE
			_eng_lp_f_t = 700.0 + 2600.0 * rpm
			_eng_amp_t = 0.42 * (0.35 + 0.65 * rpm) * air_k * duck
		"speedboat":
			var f := 38.0 + 96.0 * rpm
			_eng_osc[0]["inc_t"] = f * 0.5 * TBL / RATE            # table = 2 cycles
			_eng_osc[1]["inc_t"] = f * 0.5 * TBL / RATE * 0.99481  # -9 cents
			_eng_osc[2]["inc_t"] = f * 0.5 * TBL / RATE            # square subharmonic at f/2
			_eng_osc[2]["gain_t"] = 0.1 + 0.28 * (1.0 - clampf(rpm, 0.0, 1.0))
			_eng_lp_f_t = 200.0 + 1300.0 * rpm
			_eng_amp_t = 0.7 * (0.3 + 0.7 * rpm) * (1.1 if airborne else 1.0) * duck
			var drop := _eng_load_prev - load
			if drop > 0.04 and rpm > 0.35:
				_crackle_env = minf(0.5, _crackle_env + drop * 1.4)
			_eng_load_prev += (load - _eng_load_prev) * 0.3
		"pontoon":
			var f := 30.0 + 70.0 * rpm
			_eng_osc[0]["inc_t"] = f * TBL / RATE
			_eng_lp_f_t = 260.0 + 760.0 * rpm
			_eng_amp_t = 0.5 * (0.45 + 0.55 * rpm) * duck
		"sub":
			var f := 42.0 + 50.0 * rpm
			_eng_osc[0]["inc_t"] = f * TBL / RATE
			_eng_osc[1]["inc_t"] = f * 1.5 * TBL / RATE
			_eng_lp_f_t = 300.0 + 900.0 * rpm
			_eng_amp_t = 0.55 * (0.4 + 0.6 * rpm) * duck
		_:
			# Sailboat: wind in the rigging + occasional sail flaps.
			_sail_v.f_t = 220.0 + 900.0 * spd
			_sail_v.gain_t = (0.1 + 0.5 * _smoothstep(0.0, 1.0, spd)) * duck
			_eng_lp_f_t = 3000.0
			_eng_amp_t = 1.0 * duck
			if spd > 0.1 and _t_samples > _eng_next_flap:
				_noise_hit(BUS_ENGINE, 0.0, {"type": "bandpass", "f": 500.0 + randf() * 500.0, "q": 1.2, "dur": 0.045, "gain": 0.1 + 0.12 * spd, "a": 0.004})
				_eng_next_flap = _t_samples + int((0.22 + randf() * maxf(0.2, 1.8 - spd)) * RATE)
	# Spray: rises with speed, thins when the hull leaves the water.
	var spray := _smoothstep(0.04, 0.7, spd) * 0.34 * (0.15 if airborne else 0.45 + 0.55 * sub)
	_spray.gain_t = spray * duck
	_spray.f_t = 1500.0 + 2200.0 * spd


## Fade the engine out (boat destroyed / menu).
func stop_engine() -> void:
	_eng_amp_t = 0.0
	_spray.gain_t = 0.0
	_sail_v.gain_t = 0.0


## Derive set_engine() parameters from a BoatPhysics-like body (duck-typed: throttle, speed_kmh,
## hull.max_speed / hull.maxSpeed (m/s), airborne, boost, submersion) and drive the engine.
func drive_engine(type: String, body: Object) -> void:
	if body == null:
		return
	var thr := clampf(float(body.get("throttle")), -0.5, 1.0)
	var load := absf(thr)
	var hull = body.get("hull")
	var max_ms := 20.0
	if hull is Dictionary:
		max_ms = float(hull.get("max_speed", hull.get("maxSpeed", 20.0)))
	var kmh := float(body.get("speed_kmh"))
	var speed_frac := clampf((kmh / 3.6) / maxf(max_ms, 0.1), 0.0, 1.0)
	var airborne := bool(body.get("airborne"))
	var boost := float(body.get("boost"))
	var rpm := 0.12 + 0.55 * load + 0.33 * speed_frac
	if airborne:
		rpm += 0.3 * load
	if boost > 0.0:
		rpm += 0.1 * boost
	var sub_v = body.get("submersion")
	var submersion := float(sub_v) if sub_v != null else 1.0
	set_engine(type, clampf(rpm, 0.0, 1.2), load, speed_frac, submersion, airborne)


func _build_engine(etype: String) -> void:
	_engine_type = etype
	_eng_osc.clear()
	_eng_amp = 0.0
	_eng_lp.reset()
	_crackle_env = 0.0
	var mk := func(tbl: String, gain: float, tc_inc: float, tc_gain: float) -> Dictionary:
		return {"tbl": _tables[tbl], "phase": 0.0, "inc": 1.0, "inc_t": 1.0, "gain": gain, "gain_t": gain, "tc_inc": tc_inc, "tc_gain": tc_gain}
	match etype:
		"jetski":
			_eng_osc.append(mk.call("jetski", 0.48, 0.06, 0.06))
		"speedboat":
			_eng_osc.append(mk.call("speedboat", 0.3, 0.12, 0.1))
			_eng_osc.append(mk.call("speedboat", 0.3, 0.13, 0.1))
			_eng_osc.append(mk.call("square", 0.3, 0.12, 0.2))
		"pontoon":
			_eng_osc.append(mk.call("pontoon", 0.5, 0.2, 0.15))
		"sub":
			_eng_osc.append(mk.call("sub", 0.5, 0.15, 0.15))
			_eng_osc.append(mk.call("sine", 0.12, 0.15, 0.15))
	_sail_v.gain = 0.0
	_sail_v.gain_t = 0.0


func _render_engine(acc: PackedFloat32Array, n: int) -> void:
	# Engine stops if the game stops calling set_engine (e.g. back in the menus).
	if _t_samples - _eng_last_call > RATE / 2:
		_eng_amp_t = 0.0
		_spray.gain_t = 0.0
		_sail_v.gain_t = 0.0
	var blk_s := float(n) / RATE
	var eng := _eng
	var have := false
	if _engine_type != "" and (_eng_amp > 0.0005 or _eng_amp_t > 0.0):
		eng.fill(0.0)
		have = true
		for o in _eng_osc:
			var inc: float = o["inc"]
			var inc_t: float = o["inc_t"]
			var k_inc := 1.0 - exp(-blk_s / maxf(o["tc_inc"], 0.001))
			inc += (inc_t - inc) * k_inc
			var g: float = o["gain"]
			var g_t: float = o["gain_t"]
			g += (g_t - g) * (1.0 - exp(-blk_s / maxf(o["tc_gain"], 0.001)))
			var tbl: PackedFloat32Array = o["tbl"]
			var ph: float = o["phase"]
			for i in n:
				ph += inc
				if ph >= TBL:
					ph -= TBL
				eng[i] += tbl[int(ph)] * g
			o["phase"] = ph
			o["inc"] = inc
			o["gain"] = g
		if _engine_type == "speedboat" and _crackle_env > 0.001:
			_crackle_v.gain = _crackle_env
			_crackle_v.gain_t = _crackle_env
			_crackle_v.render(eng, n, 1.0)
			_crackle_env *= exp(-blk_s / 0.28)
		elif _engine_type == "sailboat":
			_sail_v.render(eng, n, 1.0)
		if _engine_type == "sub":
			_sub_trem += blk_s * TAU * 2.5
			if _sub_trem > TAU:
				_sub_trem -= TAU
		# Filter + amplitude
		_eng_lp_f += (_eng_lp_f_t - _eng_lp_f) * (1.0 - exp(-blk_s / 0.1))
		_eng_lp.set_lowpass(_eng_lp_f, 0.9)
		var amp_k := 1.0 - exp(-blk_s / 0.08)
		var a0 := _eng_amp
		_eng_amp += (_eng_amp_t - _eng_amp) * amp_k
		var trem := 1.0 + (0.08 * sin(_sub_trem) if _engine_type == "sub" else 0.0)
		var gain := BUS_ENGINE * trem
		_eng_lp.process_add(eng, acc, n, a0 * gain, _eng_amp * gain)
	if not have:
		_eng_amp = 0.0
	_spray.render(acc, n, BUS_ENGINE)


func _render_ambient(acc: PackedFloat32Array, n: int) -> void:
	var blk_s := float(n) / RATE
	_wind_lfo += blk_s * TAU * 0.19
	if _wind_lfo > TAU:
		_wind_lfo -= TAU
	_wind.f_t = 300.0 + 500.0 * _wind_level + 140.0 * sin(_wind_lfo)
	_wind.gain_t = _wind_level * 0.5
	_rain.gain_t = _rain_level * 0.45
	_wind.render(acc, n, BUS_AMBIENT)
	_rain.render(acc, n, BUS_AMBIENT)


## Continuous rain level 0..1 (call per frame; smoothed).
func rain(level: float) -> void:
	_rain_level = clampf(level, 0.0, 1.0)


## Continuous wind level 0..1.
func wind(level: float) -> void:
	_wind_level = clampf(level, 0.0, 1.0)


static func _smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ============================================================================ voices
func _alloc() -> _Voice:
	var best: _Voice = null
	for v in _voices:
		if not v.active:
			return v
		if best == null or v.level * v.gain < best.level * best.gain:
			best = v
	return best


## Oscillator voice with attack/hold/release; f2 + slide glide the pitch; lp = one-pole low-pass.
## p: {type, f, f2, slide, dur, a, r, gain, lp, detune}  (seconds, Hz, linear gains)
func _tone(bus: float, delay: float, p: Dictionary) -> void:
	if not ready_:
		return
	var v := _alloc()
	var f: float = p.get("f", 440.0)
	var det: float = p.get("detune", 0.0)
	if det != 0.0:
		f *= pow(2.0, det / 1200.0)
	var f2: float = p.get("f2", 0.0)
	var dur: float = p.get("dur", 0.2)
	v.start_osc(_table_for(str(p.get("type", "sine")), f), f, f2 if f2 > 0.0 else f, p.get("slide", dur) if f2 > 0.0 else 0.0,
		dur, p.get("a", 0.005), p.get("r", 0.08), float(p.get("gain", 0.2)) * bus, p.get("lp", 0.0), int(delay * RATE))


## Filtered noise burst. p: {type (lowpass|bandpass|highpass), f, f2, q, dur, a, r, gain}
func _noise_hit(bus: float, delay: float, p: Dictionary) -> void:
	if not ready_:
		return
	var v := _alloc()
	var ft := 2
	match str(p.get("type", "bandpass")):
		"lowpass": ft = 1
		"highpass": ft = 3
	var dur: float = p.get("dur", 0.1)
	var r: float = p.get("r", 0.0)
	if r <= 0.0:
		r = dur * 0.6
	v.start_noise(_noise, ft, p.get("f", 1000.0), p.get("f2", 0.0), p.get("q", 0.8), dur, p.get("a", 0.003), r,
		float(p.get("gain", 0.2)) * bus, int(delay * RATE))


# ========================================================================== one-shots
## Bow slap / landing splash, intensity 0..1. Rate-limited.
func splash(i := 0.5) -> void:
	if not ready_ or _t_samples - _last_splash < int(0.12 * RATE):
		return
	_last_splash = _t_samples
	var k := clampf(i, 0.1, 1.0)
	_noise_hit(BUS_SFX, 0.0, {"type": "lowpass", "f": 1000.0, "f2": 180.0, "q": 0.9, "dur": 0.5, "a": 0.006, "gain": 0.5 * k})
	_noise_hit(BUS_SFX, 0.02, {"type": "bandpass", "f": 2800.0, "q": 0.8, "dur": 0.22, "a": 0.01, "gain": 0.22 * k})
	_tone(BUS_SFX, 0.0, {"type": "sine", "f": 95.0, "f2": 38.0, "dur": 0.28, "a": 0.004, "r": 0.2, "gain": 0.4 * k})


## Bright two-note chime for passing a gate.
func gate() -> void:
	for pair in [[0.0, 880.0], [0.1, 1318.5]]:
		_tone(BUS_SFX, pair[0], {"type": "sine", "f": pair[1], "dur": 0.55, "a": 0.004, "r": 0.45, "gain": 0.22})
		_tone(BUS_SFX, pair[0], {"type": "triangle", "f": pair[1] * 2.0, "dur": 0.22, "a": 0.004, "r": 0.18, "gain": 0.05})


## Soft bonk for a missed / wrong-way gate.
func wrong_gate() -> void:
	_tone(BUS_SFX, 0.0, {"type": "triangle", "f": 240.0, "f2": 165.0, "dur": 0.3, "a": 0.004, "r": 0.22, "gain": 0.34, "lp": 900.0})
	_tone(BUS_SFX, 0.0, {"type": "sine", "f": 120.0, "f2": 80.0, "dur": 0.3, "a": 0.004, "r": 0.22, "gain": 0.2})
	_noise_hit(BUS_SFX, 0.0, {"type": "lowpass", "f": 500.0, "q": 0.7, "dur": 0.08, "gain": 0.18})


## Two-second rising shimmer/whoosh for a portal transition.
func portal() -> void:
	_noise_hit(BUS_SFX, 0.0, {"type": "bandpass", "f": 250.0, "f2": 3600.0, "q": 4.0, "dur": 2.0, "a": 1.3, "r": 0.6, "gain": 0.5})
	for pair in [[220.0, -6.0], [330.0, 6.0], [440.0, -5.0], [660.0, 5.0]]:
		_tone(BUS_SFX, 0.0, {"type": "triangle", "f": pair[0], "f2": pair[0] * 2.0, "slide": 2.0, "dur": 2.0, "a": 0.9, "r": 0.7, "gain": 0.08, "detune": pair[1], "lp": 2600.0})
	for pair in [[1.55, 1568.0], [1.65, 2093.0], [1.75, 2637.0]]:
		_tone(BUS_SFX, pair[0], {"type": "sine", "f": pair[1], "dur": 0.35, "a": 0.004, "r": 0.3, "gain": 0.14})


## Countdown beeps: 3, 2, 1 short; 0 = "GO!" higher and longer.
func countdown(n: int) -> void:
	if n > 0:
		_tone(BUS_SFX, 0.0, {"type": "triangle", "f": 660.0, "dur": 0.15, "a": 0.005, "r": 0.08, "gain": 0.3, "lp": 2400.0})
		_tone(BUS_SFX, 0.0, {"type": "sine", "f": 660.0, "dur": 0.15, "a": 0.005, "r": 0.08, "gain": 0.18})
	else:
		_tone(BUS_SFX, 0.0, {"type": "triangle", "f": 990.0, "dur": 0.6, "a": 0.006, "r": 0.35, "gain": 0.34, "lp": 3200.0})
		_tone(BUS_SFX, 0.0, {"type": "sine", "f": 1320.0, "dur": 0.6, "a": 0.006, "r": 0.35, "gain": 0.1})


## Finish fanfare: 1st triumphant, 2nd/3rd happy, 4th+ encouraging.
func finish(place := 1) -> void:
	var base := 523.25
	var steps: Array
	var durs: Array
	var opts: Dictionary
	if place <= 1:
		steps = [0, 4, 7, 12, 7, 12]
		durs = [0.16, 0.16, 0.16, 0.5, 0.16, 0.9]
		opts = {"type": "sawtooth", "a": 0.01, "gain": 0.26, "lp": 1900.0, "octave": true}
	elif place <= 3:
		steps = [0, 4, 7, 12]
		durs = [0.16, 0.16, 0.16, 0.7]
		opts = {"type": "triangle", "a": 0.01, "gain": 0.26, "lp": 2600.0, "octave": true}
	else:
		steps = [0, 2, 4]
		durs = [0.22, 0.22, 0.7]
		opts = {"type": "sine", "a": 0.02, "gain": 0.3}
	var t := 0.0
	for i in steps.size():
		var f := base * pow(2.0, float(steps[i]) / 12.0)
		var dur: float = durs[i]
		var p := opts.duplicate()
		p["f"] = f
		p["dur"] = dur
		p["r"] = dur * 0.5
		_tone(BUS_SFX, t, p)
		if opts.get("octave", false):
			_tone(BUS_SFX, t, {"type": "triangle", "f": f * 2.0, "dur": dur, "a": opts["a"], "r": dur * 0.5, "gain": float(opts["gain"]) * 0.25})
		t += dur * 0.92


## Boat horn per type (sub = sonar ping).
func horn(type := "speedboat") -> void:
	var etype: String = ENGINE_TYPES.get(type, "speedboat")
	match etype:
		"jetski":
			_tone(BUS_SFX, 0.0, {"type": "square", "f": 640.0, "f2": 600.0, "dur": 0.22, "a": 0.008, "r": 0.06, "gain": 0.26, "lp": 1500.0})
		"pontoon":
			_tone(BUS_SFX, 0.0, {"type": "sawtooth", "f": 320.0, "f2": 680.0, "slide": 0.6, "dur": 0.8, "a": 0.03, "r": 0.2, "gain": 0.3, "lp": 1700.0})
			_tone(BUS_SFX, 0.0, {"type": "triangle", "f": 640.0, "f2": 1360.0, "slide": 0.6, "dur": 0.8, "a": 0.03, "r": 0.2, "gain": 0.1})
		"sailboat":
			for trip in [[1.0, 0.34, 1.9], [2.0, 0.18, 1.4], [2.98, 0.11, 1.0], [4.2, 0.06, 0.7], [5.4, 0.03, 0.5]]:
				_tone(BUS_SFX, 0.0, {"type": "sine", "f": 660.0 * trip[0], "dur": trip[2], "a": 0.003, "r": trip[2] * 0.9, "gain": trip[1]})
		"sub":
			_tone(BUS_SFX, 0.0, {"type": "sine", "f": 1250.0, "f2": 1180.0, "dur": 0.9, "a": 0.004, "r": 0.85, "gain": 0.3})
			_tone(BUS_SFX, 0.0, {"type": "sine", "f": 2500.0, "dur": 0.25, "a": 0.004, "r": 0.2, "gain": 0.06})
			_tone(BUS_SFX, 0.38, {"type": "sine", "f": 1250.0, "f2": 1180.0, "dur": 0.7, "a": 0.01, "r": 0.65, "gain": 0.12, "lp": 1800.0})
		_:
			for f in [196.0, 247.0]:
				_tone(BUS_SFX, 0.0, {"type": "sawtooth", "f": f, "dur": 0.75, "a": 0.04, "r": 0.15, "gain": 0.2, "lp": 1100.0})
				_tone(BUS_SFX, 0.0, {"type": "square", "f": f * 0.5, "dur": 0.75, "a": 0.04, "r": 0.15, "gain": 0.08, "lp": 700.0})


## Sparkle for collecting a star.
func star() -> void:
	var fs := [1568.0, 2093.0, 2637.0, 3136.0]
	for i in fs.size():
		_tone(BUS_SFX, i * 0.05, {"type": "sine", "f": fs[i], "dur": 0.1, "a": 0.003, "r": 0.06, "gain": 0.22})
	_tone(BUS_SFX, 0.2, {"type": "triangle", "f": 3136.0, "dur": 0.45, "a": 0.01, "r": 0.4, "gain": 0.08, "detune": 6.0})
	_tone(BUS_SFX, 0.2, {"type": "sine", "f": 3136.0, "dur": 0.45, "a": 0.01, "r": 0.4, "gain": 0.08, "detune": -6.0})


## UI tap.
func click() -> void:
	_tone(BUS_SFX, 0.0, {"type": "sine", "f": 1800.0, "f2": 1400.0, "dur": 0.04, "a": 0.002, "r": 0.025, "gain": 0.3})
	_noise_hit(BUS_SFX, 0.0, {"type": "highpass", "f": 3000.0, "dur": 0.025, "a": 0.001, "gain": 0.18})


## Thunder arriving distance/340 s after the flash; louder and crackier when close.
func lightning(distance := 600.0) -> void:
	var t := maxf(0.0, distance) / 340.0
	var amp := clampf(1.25 - distance / 3000.0, 0.15, 1.0)
	if distance < 900.0:
		_noise_hit(BUS_SFX, t, {"type": "highpass", "f": 700.0, "q": 0.7, "dur": 0.09, "a": 0.002, "gain": 0.3 * amp})
	_noise_hit(BUS_SFX, t + 0.03, {"type": "lowpass", "f": 220.0, "f2": 55.0, "q": 1.3, "dur": 3.2, "a": 0.12, "r": 2.6, "gain": 0.55 * amp})
	_noise_hit(BUS_SFX, t + 0.5, {"type": "lowpass", "f": 140.0, "f2": 45.0, "q": 1.1, "dur": 2.6, "a": 0.35, "r": 1.9, "gain": 0.35 * amp})


# ============================================================================== music
## Start/stop the procedural pentatonic loop.
func music(on: bool) -> void:
	if on and not _music_on:
		_m_step = 0
		_m_next = _t_samples + RATE / 10
	_music_on = on
	_music_gain_t = 1.0 if on else 0.0


## "hub" | "race" | "storm"
func mood(m: String) -> void:
	if MOODS.has(m):
		mood_name = m


func set_music_mood(m: String) -> void:
	mood(m)


func _render_music(_acc: PackedFloat32Array, n: int) -> void:
	_music_gain += (_music_gain_t - _music_gain) * 0.1
	if not _music_on:
		return
	var md: Dictionary = MOODS[mood_name]
	var step_len := int(60.0 / md["bpm"] / 2.0 * RATE)  # eighth notes
	while _m_next < _t_samples + n:
		var delay := float(maxi(0, _m_next - _t_samples)) / RATE
		_music_step(delay, _m_step, md)
		_m_step += 1
		_m_next += step_len


func _music_step(delay: float, step: int, md: Dictionary) -> void:
	var eighth := step % 8
	var beat := eighth >> 1
	var bar := step / 8
	var prog: Array = PROG_MINOR if md["minor"] else PROG_MAJOR
	var chord: Array = prog[(bar / 4) % prog.size()]
	var root: float = md["root"]
	var duck := 0.5 if _paused else 1.0
	var mg := BUS_MUSIC * _music_gain * duck
	var cutoff: float = md["cutoff"]
	# Arpeggio an octave above the key root (through the mood's low-pass).
	var arp: Array = ARP_B if (bar % 2) else ARP_A
	var idx: int = arp[eighth]
	var f := root * pow(2.0, float(chord[idx] + 12) / 12.0)
	_tone(mg, delay, {"type": "triangle", "f": f, "dur": 0.24, "a": 0.008, "r": 0.16, "gain": 0.5 * float(md["arp_gain"]), "lp": cutoff})
	# Bass on beats 1 and 3.
	if eighth == 0 or eighth == 4:
		var bass_oct := -12 if root < 250.0 else -24
		_tone(mg, delay, {"type": "sine", "f": root * pow(2.0, float(chord[0] + bass_oct) / 12.0), "dur": 0.45, "a": 0.01, "r": 0.2, "gain": 0.55, "lp": cutoff})
	# Drums: sine thump + noise hats.
	if (eighth & 1) == 0 and (md["kicks"] as Array).has(beat):
		_tone(mg, delay, {"type": "sine", "f": 150.0, "f2": 45.0, "slide": 0.09, "dur": 0.18, "a": 0.002, "r": 0.12, "gain": 0.7})
	_noise_hit(mg, delay, {"type": "highpass", "f": 6500.0, "dur": 0.07 if (eighth & 1) else 0.035, "a": 0.001, "gain": 0.16 if (eighth & 1) else 0.1})


# ======================================================================== diagnostics
## RMS / peak of the Master bus since the previous call (installs an AudioEffectCapture lazily).
func debug_level() -> Dictionary:
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.5
		AudioServer.add_bus_effect(0, _capture)
		return {"rms": 0.0, "peak": 0.0, "frames": 0}
	var n := _capture.get_frames_available()
	if n <= 0:
		return {"rms": 0.0, "peak": 0.0, "frames": 0}
	var buf := _capture.get_buffer(n)
	var sum := 0.0
	var peak := 0.0
	for v in buf:
		var a := absf(v.x)
		sum += v.x * v.x
		if a > peak:
			peak = a
	return {"rms": sqrt(sum / float(n)), "peak": peak, "frames": n}


func get_harness_state() -> Dictionary:
	var active := 0
	for v in _voices:
		if v.active:
			active += 1
	return {"audio_voices": active, "engine": _engine_type, "music": _music_on, "mood": mood_name}


# ============================================================================ classes
class _Biquad:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var z1 := 0.0
	var z2 := 0.0
	var _f := -1.0
	var _q := -1.0
	var _kind := 0

	func reset() -> void:
		z1 = 0.0
		z2 = 0.0

	func set_lowpass(f: float, q: float) -> void:
		configure(1, f, q)

	func configure(kind: int, f: float, q: float) -> void:
		if kind == _kind and absf(f - _f) < 0.5 and q == _q:
			return
		_kind = kind
		_f = f
		_q = q
		f = clampf(f, 20.0, RATE * 0.45)
		var w0 := TAU * f / RATE
		var cw := cos(w0)
		var alpha := sin(w0) / (2.0 * maxf(q, 0.05))
		var a0 := 1.0 + alpha
		match kind:
			1:
				b0 = (1.0 - cw) * 0.5 / a0
				b1 = (1.0 - cw) / a0
				b2 = b0
			3:
				b0 = (1.0 + cw) * 0.5 / a0
				b1 = -(1.0 + cw) / a0
				b2 = b0
			_:
				b0 = alpha / a0
				b1 = 0.0
				b2 = -alpha / a0
		a1 = -2.0 * cw / a0
		a2 = (1.0 - alpha) / a0

	## acc[i] += filter(src[i]) * lerp(g0, g1, i/n)
	func process_add(src: PackedFloat32Array, acc: PackedFloat32Array, n: int, g0: float, g1: float) -> void:
		var lb0 := b0
		var lb1 := b1
		var lb2 := b2
		var la1 := a1
		var la2 := a2
		var s1 := z1
		var s2 := z2
		var g := g0
		var dg := (g1 - g0) / float(n)
		for i in n:
			var x := src[i]
			var y := lb0 * x + s1
			s1 = lb1 * x - la1 * y + s2
			s2 = lb2 * x - la2 * y
			g += dg
			acc[i] += y * g
		z1 = s1
		z2 = s2


## Continuous filtered-noise voice (spray, wind, rain, sail wind, exhaust crackle).
class _NoiseVoice:
	var table: PackedFloat32Array
	var pos := 0
	var gain := 0.0
	var gain_t := 0.0
	var f := 1000.0
	var f_t := 1000.0
	var q := 0.7
	var kind := 2
	var bq := _Biquad.new()

	func set_filter(k: int, f0: float, q0: float) -> void:
		kind = k
		f = f0
		f_t = f0
		q = q0

	func render(acc: PackedFloat32Array, n: int, bus: float) -> void:
		var g0 := gain * bus
		gain += (gain_t - gain) * 0.12
		f += (f_t - f) * 0.1
		var g1 := gain * bus
		if g0 < 0.0002 and g1 < 0.0002:
			gain = gain_t if gain_t < 0.0002 else gain
			return
		bq.configure(kind, f, q)
		var tbl := table
		var p := pos
		var lb0 := bq.b0
		var lb1 := bq.b1
		var lb2 := bq.b2
		var la1 := bq.a1
		var la2 := bq.a2
		var s1 := bq.z1
		var s2 := bq.z2
		var g := g0
		var dg := (g1 - g0) / float(n)
		for i in n:
			var x := tbl[p]
			p = (p + 1) & NOISE_MASK
			var y := lb0 * x + s1
			s1 = lb1 * x - la1 * y + s2
			s2 = lb2 * x - la2 * y
			g += dg
			acc[i] += y * g
		pos = p
		bq.z1 = s1
		bq.z2 = s2


## One-shot voice: wavetable oscillator or filtered noise with attack / hold / exponential release.
class _Voice:
	var active := false
	var is_noise := false
	var table: PackedFloat32Array
	var phase := 0.0
	var inc := 1.0
	var glide_mul := 1.0
	var glide_left := 0
	var gain := 0.0
	var level := 0.0
	var att_step := 0.0
	var att_left := 0
	var hold_left := 0
	var rel_left := 0
	var rel_mul := 1.0
	var delay := 0
	var lp_k := 0.0       # one-pole low-pass coefficient (0 = off)
	var lp_y := 0.0
	var npos := 0
	var kind := 2
	var f := 1000.0
	var f_end := 1000.0
	var f_mul := 1.0
	var q := 0.8
	var bq := _Biquad.new()

	func _env(dur: float, a: float, r: float, delay_samples: int) -> void:
		var rate := float(RATE)
		delay = maxi(0, delay_samples)
		att_left = maxi(1, int(a * rate))
		att_step = 1.0 / float(att_left)
		var rel := clampf(r, 0.002, dur)
		hold_left = maxi(0, int((dur - rel) * rate) - att_left)
		rel_left = maxi(1, int(rel * rate))
		rel_mul = exp(-6.9 / float(rel_left))   # -60 dB over the release
		level = 0.0
		active = true

	func start_osc(tbl: PackedFloat32Array, f0: float, f1: float, slide: float, dur: float, a: float, r: float, g: float, lp: float, delay_samples: int) -> void:
		is_noise = false
		table = tbl
		phase = 0.0
		inc = f0 * TBL / RATE
		gain = g
		if f1 != f0 and slide > 0.0:
			glide_left = maxi(1, int(slide * RATE))
			glide_mul = pow(f1 / f0, 1.0 / float(glide_left))
		else:
			glide_left = 0
			glide_mul = 1.0
		if lp > 0.0:
			lp_k = 1.0 - exp(-TAU * clampf(lp, 20.0, RATE * 0.45) / RATE)
		else:
			lp_k = 0.0
		lp_y = 0.0
		_env(dur, a, r, delay_samples)

	func start_noise(tbl: PackedFloat32Array, k: int, f0: float, f1: float, q0: float, dur: float, a: float, r: float, g: float, delay_samples: int) -> void:
		is_noise = true
		table = tbl
		npos = randi() & NOISE_MASK
		kind = k
		f = f0
		f_end = f1 if f1 > 0.0 else f0
		q = q0
		gain = g
		bq.reset()
		bq._kind = -1
		var blocks := maxf(1.0, dur * RATE / BLOCK)
		f_mul = pow(f_end / f0, 1.0 / blocks) if f1 > 0.0 else 1.0
		_env(dur, a, r, delay_samples)

	func render(acc: PackedFloat32Array, n: int) -> void:
		var start := 0
		if delay > 0:
			if delay >= n:
				delay -= n
				return
			start = delay
			delay = 0
		var lvl := level
		var g := gain
		var al := att_left
		var ast := att_step
		var hl := hold_left
		var rl := rel_left
		var rm := rel_mul
		if is_noise:
			bq.configure(kind, f, q)
			f *= f_mul
			var tbl := table
			var p := npos
			var lb0 := bq.b0
			var lb1 := bq.b1
			var lb2 := bq.b2
			var la1 := bq.a1
			var la2 := bq.a2
			var s1 := bq.z1
			var s2 := bq.z2
			for i in range(start, n):
				if al > 0:
					lvl += ast
					al -= 1
				elif hl > 0:
					hl -= 1
				elif rl > 0:
					lvl *= rm
					rl -= 1
				else:
					active = false
					break
				var x := tbl[p]
				p = (p + 1) & NOISE_MASK
				var y := lb0 * x + s1
				s1 = lb1 * x - la1 * y + s2
				s2 = lb2 * x - la2 * y
				acc[i] += y * lvl * g
			npos = p
			bq.z1 = s1
			bq.z2 = s2
		else:
			var tbl := table
			var ph := phase
			var ic := inc
			var gl := glide_left
			var gm := glide_mul
			var lk := lp_k
			var ly := lp_y
			for i in range(start, n):
				if al > 0:
					lvl += ast
					al -= 1
				elif hl > 0:
					hl -= 1
				elif rl > 0:
					lvl *= rm
					rl -= 1
				else:
					active = false
					break
				if gl > 0:
					ic *= gm
					gl -= 1
				ph += ic
				if ph >= TBL:
					ph -= TBL
				var s := tbl[int(ph)]
				if lk > 0.0:
					ly += (s - ly) * lk
					s = ly
				acc[i] += s * lvl * g
			phase = ph
			inc = ic
			glide_left = gl
			lp_y = ly
		level = lvl
		att_left = al
		hold_left = hl
		rel_left = rl
