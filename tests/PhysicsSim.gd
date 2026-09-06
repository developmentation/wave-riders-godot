extends SceneTree
## Headless physics checks — port of tools/physics-sim.mjs (boat half).
##   godot --headless --path . -s tests/PhysicsSim.gd [hull,hull,...]
## Every hull: full throttle for 5 s on flat water, then full right lock; prints
## speed, heading, yaw rate and bank once per second, then checks: no capsizing
## (bank <= 25 deg), yaw rate at lock in range, top speed within 6 % of the web sim.
## Targets are what `node tools/physics-sim.mjs <hull>` prints in the web project
## (flat water, no boost, wind = null): the game's boosted tops are ~18 % higher.
## The pontoon (0.42 rad/s) and the sailboat (0.23) turn slower than 0.5 rad/s in the
## web too, so the yaw window is 0.2..1.6 for those two and 0.5..1.6 otherwise.

const EXPECTED_KMH := {
	"jetski": 67.0, "speedboat": 80.0, "sailboat": 38.0, "pontoon": 42.0, "fishing": 35.0,
	"tug": 29.0, "airboat": 71.0, "towboat": 83.0, "rowboat": 12.0,
}
const EXPECTED_YAW := {
	"jetski": 1.54, "speedboat": 1.03, "sailboat": 0.23, "pontoon": 0.42, "fishing": 0.54,
	"tug": 0.69, "airboat": 1.40, "towboat": 0.86, "rowboat": 1.10,
}


func _init() -> void:
	var ids: Array = Hulls.IDS.duplicate()
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			ids = a.split(",")
	var failures := 0
	for name in ids:
		var hull: Dictionary = Hulls.HULLS[name]
		var b := BoatPhysics.new()
		b.set_hull(hull)
		b.wind = {}   # like the web sim: no point-of-sail model
		b.set_pose(0, 0, 0, 0)
		var dt := 1.0 / 60.0
		var t := 0.0
		var last := 0.0
		var max_bank := 0.0
		var top := 0.0
		var yaw_sum := 0.0
		var yaw_n := 0
		var lines: PackedStringArray = []
		for i in 60 * 12:
			b.throttle = 1.0
			b.steer = 1.0 if t > 5.0 else 0.0
			b.advance(dt)
			t += dt
			var bank := rad_to_deg(asin(clampf(b.right.y, -1, 1)))
			max_bank = maxf(max_bank, absf(bank))
			if t <= 5.0:
				top = maxf(top, b.speed_kmh)
			if t > 7.0:
				yaw_sum += -b.angular.dot(b.up)   # positive = bow toward -X = screen right
				yaw_n += 1
			if t - last >= 1.0:
				last = t
				lines.append("%ds v=%.0f hdg=%.2f yaw=%.2f bank=%.0fdeg sub=%.2f" % [roundi(t), b.speed_kmh, b.heading, b.angular.y, bank, b.submersion])
		var yaw := yaw_sum / maxi(yaw_n, 1)
		print(name)
		print("\n".join(lines))
		var exp_kmh: float = EXPECTED_KMH.get(name, top)
		var ok_speed := absf(top - exp_kmh) <= maxf(3.0, exp_kmh * 0.06)
		var ok_bank := max_bank <= 25.0
		var yaw_min := 0.2 if name in ["sailboat", "pontoon"] else 0.5
		var ok_yaw := yaw >= yaw_min and yaw <= 1.6
		print("  top %.1f km/h (web %.0f) %s | max bank %.1f deg %s | lock yaw %.2f rad/s (web %.2f) %s" % [
			top, exp_kmh, "ok" if ok_speed else "FAIL", max_bank, "ok" if ok_bank else "FAIL", yaw, EXPECTED_YAW.get(name, yaw), "ok" if ok_yaw else "FAIL"])
		if not (ok_speed and ok_bank and ok_yaw):
			failures += 1
		b.free()
	print("\nall hull checks passed" if failures == 0 else "\n%d hull(s) FAILED" % failures)
	quit(1 if failures > 0 else 0)
