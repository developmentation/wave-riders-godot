class_name Hulls
## Hull table for BoatPhysics — a faithful copy of HULLS in the web game's
## src/game/BoatPhysics.js (same numbers). Units: metres, seconds, kilograms.
## +Z is the hull's forward axis; buoyancy points are [x, y, z] in body space.

## Buoyancy spring stiffness factor; at rest each point sinks draft / SPRING_FACTOR.
## Boats.gd uses it to place the hull at the waterline.
const SPRING_FACTOR := 1.8

const HULLS := {
	"jetski": {
		"length": 3.3, "width": 1.25, "mass": 380.0, "draft": 0.32,
		"thrust": 5200.0, "max_speed": 22.0, "steer_torque": 0.6, "rudder_lift": 0.25, "max_yaw": 1.5,
		"drag_long": 0.055, "drag_lat": 1.2, "planing": 0.85, "roll": 1.6, "bounce": 1.3,
		# Point height = -draft/1.35 puts the body origin at the resting waterline.
		"buoyancy_points": [[0.0, -0.24, 1.35], [-0.5, -0.24, -0.2], [0.5, -0.24, -0.2], [-0.45, -0.24, -1.4], [0.45, -0.24, -1.4]],
		"label": "Jet Ski",
	},
	"speedboat": {
		"length": 6.4, "width": 2.3, "mass": 1500.0, "draft": 0.5,
		"thrust": 18000.0, "max_speed": 28.0, "steer_torque": 0.7, "rudder_lift": 0.32, "max_yaw": 1.1,
		"drag_long": 0.05, "drag_lat": 1.4, "planing": 0.8, "roll": 1.1, "bounce": 1.0,
		"buoyancy_points": [[0.0, -0.37, 2.8], [-0.9, -0.37, 1.0], [0.9, -0.37, 1.0], [-1.0, -0.37, -1.2], [1.0, -0.37, -1.2], [0.0, -0.37, -2.8]],
		"label": "Speedboat",
	},
	"sailboat": {
		"length": 8.0, "width": 2.6, "mass": 2600.0, "draft": 0.6,
		"thrust": 14000.0, "max_speed": 12.0, "steer_torque": 0.55, "rudder_lift": 0.6, "max_yaw": 0.7,
		"drag_long": 0.08, "drag_lat": 2.2, "planing": 0.0, "roll": 0.55, "bounce": 0.7, "sail": true,
		"buoyancy_points": [[0.0, -0.45, 3.6], [-1.1, -0.45, 1.2], [1.1, -0.45, 1.2], [-1.15, -0.45, -1.6], [1.15, -0.45, -1.6], [0.0, -0.45, -3.7]],
		"label": "Sailboat",
	},
	"pontoon": {
		"length": 7.0, "width": 2.6, "mass": 1900.0, "draft": 0.35,
		"thrust": 14000.0, "max_speed": 14.0, "steer_torque": 0.6, "rudder_lift": 0.35, "max_yaw": 0.8,
		"drag_long": 0.09, "drag_lat": 1.6, "planing": 0.1, "roll": 0.3, "bounce": 0.6,
		"buoyancy_points": [[-1.0, -0.26, 3.2], [1.0, -0.26, 3.2], [-1.0, -0.26, 0.0], [1.0, -0.26, 0.0], [-1.0, -0.26, -3.2], [1.0, -0.26, -3.2]],
		"label": "Pontoon",
	},
	# Kenney boat-fishing-small: a chunky displacement hull, very steady, ~35 km/h.
	"fishing": {
		"length": 6.0, "width": 2.6, "mass": 1800.0, "draft": 0.55,
		"thrust": 12000.0, "max_speed": 10.6, "steer_torque": 0.6, "rudder_lift": 2.2, "max_yaw": 0.8,
		"drag_long": 0.07, "drag_lat": 1.9, "planing": 0.15, "roll": 0.5, "bounce": 0.7,
		"buoyancy_points": [[0.0, -0.41, 2.6], [-0.9, -0.41, 0.9], [0.9, -0.41, 0.9], [-0.95, -0.41, -1.2], [0.95, -0.41, -1.2], [0.0, -0.41, -2.6]],
		"label": "Fishing Boat",
	},
	# Kenney boat-tug-a/b/c: slow, heavy, shoulders through waves, barely rolls, ~28 km/h.
	"tug": {
		"length": 6.0, "width": 3.0, "mass": 3400.0, "draft": 0.7,
		"thrust": 17000.0, "max_speed": 8.6, "steer_torque": 1.0, "rudder_lift": 4.5, "max_yaw": 0.75,
		"drag_long": 0.1, "drag_lat": 2.4, "planing": 0.0, "roll": 0.35, "bounce": 1.4,
		"buoyancy_points": [[0.0, -0.52, 2.6], [-1.05, -0.52, 0.9], [1.05, -0.52, 0.9], [-1.1, -0.52, -1.2], [1.1, -0.52, -1.2], [0.0, -0.52, -2.6]],
		"label": "Tugboat",
	},
	# Kenney boat-fan: flat-bottomed airboat, fast, very little lateral grip, ~75 km/h.
	"airboat": {
		"length": 5.0, "width": 3.0, "mass": 700.0, "draft": 0.25,
		"thrust": 9500.0, "max_speed": 28.0, "steer_torque": 1.0, "rudder_lift": 0.14, "max_yaw": 1.4,
		"drag_long": 0.04, "drag_lat": 0.3, "planing": 0.9, "roll": 0.35, "bounce": 1.1,
		"buoyancy_points": [[-0.9, -0.185, 2.1], [0.9, -0.185, 2.1], [-1.1, -0.185, 0.0], [1.1, -0.185, 0.0], [-1.0, -0.185, -2.1], [1.0, -0.185, -2.1]],
		"label": "Airboat",
	},
	# Kenney boat-tow-a/b: wakeboard tow boat, speedboat class with a wider, heavier hull, ~85 km/h.
	"towboat": {
		"length": 7.0, "width": 3.0, "mass": 1900.0, "draft": 0.5,
		"thrust": 23000.0, "max_speed": 31.0, "steer_torque": 0.65, "rudder_lift": 0.3, "max_yaw": 1.0,
		"drag_long": 0.05, "drag_lat": 1.5, "planing": 0.8, "roll": 1.0, "bounce": 1.0,
		"buoyancy_points": [[0.0, -0.37, 3.1], [-1.15, -0.37, 1.1], [1.15, -0.37, 1.1], [-1.25, -0.37, -1.3], [1.25, -0.37, -1.3], [0.0, -0.37, -3.1]],
		"label": "Tow Boat",
	},
	# Kenney boat-row-small: a kid rowing. Silly slow (~12 km/h) but turns on the spot.
	"rowboat": {
		"length": 3.2, "width": 1.5, "mass": 220.0, "draft": 0.22,
		"thrust": 950.0, "max_speed": 3.9, "steer_torque": 2.0, "rudder_lift": 0.3, "max_yaw": 1.1,
		# High longitudinal drag: the oars have to keep pushing at cruise, which is what gives the big steer authority.
		"drag_long": 0.28, "drag_lat": 1.6, "planing": 0.0, "roll": 0.6, "bounce": 0.6,
		"buoyancy_points": [[0.0, -0.163, 1.35], [-0.55, -0.163, 0.3], [0.55, -0.163, 0.3], [-0.5, -0.163, -1.0], [0.5, -0.163, -1.0], [0.0, -0.163, -1.4]],
		"label": "Rowboat",
	},
	# Kenney ship-ocean-liner-small: a big, slow, very steady passenger ferry (~32 km/h).
	"ferry": {
		"length": 24.0, "width": 7.5, "mass": 45000.0, "draft": 1.6,
		"thrust": 160000.0, "max_speed": 9.0, "steer_torque": 0.9, "rudder_lift": 6.0, "max_yaw": 0.3,
		"drag_long": 0.08, "drag_lat": 3.0, "planing": 0.0, "roll": 0.2, "bounce": 1.8,
		"buoyancy_points": [[-3.0, -1.185, 9.0], [3.0, -1.185, 9.0], [-3.4, -1.185, 3.0], [3.4, -1.185, 3.0], [-3.4, -1.185, -3.0], [3.4, -1.185, -3.0], [-3.0, -1.185, -9.0], [3.0, -1.185, -9.0]],
		"label": "Ferry",
	},
}

## Order used by the garage and the fleet lineup.
const IDS := ["jetski", "speedboat", "sailboat", "pontoon", "fishing", "tug", "airboat", "towboat", "rowboat"]


## Body-origin height above still water once the springs carry the weight
## (negative: the origin sits below the surface). BoatPhysics sizes each
## spring so the points settle at depth draft / SPRING_FACTOR.
static func rest_height(hull: Dictionary) -> float:
	var pts: Array = hull.buoyancy_points
	var mean_y := 0.0
	for p in pts:
		mean_y += float(p[1])
	mean_y /= pts.size()
	return -float(hull.draft) / SPRING_FACTOR - mean_y
