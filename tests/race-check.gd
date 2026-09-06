extends Node
## Race acceptance check for tests/RaceTest.tscn (headless-friendly). Every second it prints
## `RACECHECK t=<s> ...` with the standings; at `check_at` seconds it prints
## `RACECHECK RESULT PASS|FAIL ...` — PASS when every AI has passed >= min_gates gates with no stuck
## rescues. Run:  node tools/godot-run.mjs --seconds 92 --tag race --scene res://tests/RaceTest.tscn --script "throttle:90"
## or headless:   godot --headless --path . res://tests/RaceTest.tscn -- --seconds=92

@export var check_at := 90.0
@export var min_gates := 6
@export var main_path: NodePath = ^"../Main"

var _t := 0.0
var _last := -1.0
var _done := false


func _process(dt: float) -> void:
	_t += dt
	var main := get_node_or_null(main_path)
	if main == null or not ("race" in main) or main.race == null:
		return
	var race = main.race
	if _t - _last >= 1.0:
		_last = _t
		var parts := PackedStringArray()
		for s in race.standings:
			parts.append("%d:%s(L%d g%d n%d %dkmh%s)" % [s.position, s.name, s.lap, s.gate, s.gates_total, int(s.speed_kmh), (" STUCKx%d" % s.stuck_nudges) if s.stuck_nudges > 0 else ""])
		print("RACECHECK t=%.0f state=%s time=%.1f %s" % [_t, race.state, race.time, " ".join(parts)])
	if not _done and _t >= check_at:
		_done = true
		var ok := true
		var why := PackedStringArray()
		var ai_seen := 0
		for s in race.standings:
			if not s.ai:
				continue
			ai_seen += 1
			if s.gates_total < min_gates:
				ok = false
				why.append("%s only %d gates" % [s.name, s.gates_total])
			if s.stuck_nudges > 0:
				ok = false
				why.append("%s stuck x%d" % [s.name, s.stuck_nudges])
		if ai_seen == 0:
			ok = false
			why.append("no AI racers")
		print("RACECHECK RESULT %s ai=%d %s" % ["PASS" if ok else "FAIL", ai_seen, "; ".join(why)])
