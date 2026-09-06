class_name SaveData
## Persistent player data: stars per world (user://stars.json, the web game's
## localStorage "waveriders.stars.v1") and small preferences (user://prefs.json: matte, muted, boat).

const STARS_PATH := "user://stars.json"
const PREFS_PATH := "user://prefs.json"


static func load_stars() -> Dictionary:
	return _load(STARS_PATH)


static func save_stars(stars: Dictionary) -> void:
	_save(STARS_PATH, stars)


## Record a result for `world_id`; returns the updated entry {stars, best}.
static func record_result(stars: Dictionary, world_id: String, place: int, time: float) -> Dictionary:
	var got := 3 if place == 1 else (2 if place == 2 else 1)
	var prev: Dictionary = stars.get(world_id, {"stars": 0, "best": INF})
	var best_prev := float(prev.get("best", INF))
	if best_prev <= 0.0:
		best_prev = INF
	var entry := {"stars": maxi(int(prev.get("stars", 0)), got), "best": minf(best_prev, time)}
	stars[world_id] = entry
	save_stars(stars)
	return entry


static func total_stars(stars: Dictionary) -> int:
	var n := 0
	for k in stars:
		n += int(stars[k].get("stars", 0))
	return n


static func load_prefs() -> Dictionary:
	return _load(PREFS_PATH)


static func save_prefs(prefs: Dictionary) -> void:
	_save(PREFS_PATH, prefs)


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _save(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveData: cannot write %s" % path)
		return
	# INF is not JSON; store best times as 0 = none.
	var clean := data.duplicate(true)
	for k in clean:
		if clean[k] is Dictionary and is_inf(float(clean[k].get("best", 0.0))):
			clean[k]["best"] = 0.0
	f.store_string(JSON.stringify(clean))
