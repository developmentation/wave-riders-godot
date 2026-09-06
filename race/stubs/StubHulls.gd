class_name StubHulls
## Hull table for the race stubs: the same numbers as the web game's BoatPhysics.js HULLS,
## in snake_case. boats/Hulls.gd (the real port) supersedes this; Race.gd reads either
## spelling (max_speed / maxSpeed) so both work.

const HULLS := {
	"jetski": {
		"length": 3.3, "width": 1.25, "mass": 380.0, "draft": 0.32,
		"thrust": 5200.0, "max_speed": 22.0, "steer_torque": 0.6, "rudder_lift": 0.25, "max_yaw": 1.5,
		"drag_long": 0.055, "drag_lat": 1.2, "planing": 0.85, "roll": 1.6, "bounce": 1.3, "label": "Jet Ski",
	},
	"speedboat": {
		"length": 6.4, "width": 2.3, "mass": 1500.0, "draft": 0.5,
		"thrust": 18000.0, "max_speed": 28.0, "steer_torque": 0.7, "rudder_lift": 0.32, "max_yaw": 1.1,
		"drag_long": 0.05, "drag_lat": 1.4, "planing": 0.8, "roll": 1.1, "bounce": 1.0, "label": "Speedboat",
	},
	"sailboat": {
		"length": 8.0, "width": 2.6, "mass": 2600.0, "draft": 0.6,
		"thrust": 14000.0, "max_speed": 12.0, "steer_torque": 0.55, "rudder_lift": 0.6, "max_yaw": 0.7,
		"drag_long": 0.08, "drag_lat": 2.2, "planing": 0.0, "roll": 0.55, "bounce": 0.7, "sail": true, "label": "Sailboat",
	},
	"pontoon": {
		"length": 7.0, "width": 2.6, "mass": 1900.0, "draft": 0.35,
		"thrust": 14000.0, "max_speed": 14.0, "steer_torque": 0.6, "rudder_lift": 0.35, "max_yaw": 0.8,
		"drag_long": 0.09, "drag_lat": 1.6, "planing": 0.1, "roll": 0.3, "bounce": 0.6, "label": "Pontoon",
	},
	"fishing": {
		"length": 6.0, "width": 2.6, "mass": 1800.0, "draft": 0.55,
		"thrust": 12000.0, "max_speed": 10.6, "steer_torque": 0.6, "rudder_lift": 2.2, "max_yaw": 0.8,
		"drag_long": 0.07, "drag_lat": 1.9, "planing": 0.15, "roll": 0.5, "bounce": 0.7, "label": "Fishing Boat",
	},
	"tug": {
		"length": 6.0, "width": 3.0, "mass": 3400.0, "draft": 0.7,
		"thrust": 17000.0, "max_speed": 8.6, "steer_torque": 1.0, "rudder_lift": 4.5, "max_yaw": 0.75,
		"drag_long": 0.1, "drag_lat": 2.4, "planing": 0.0, "roll": 0.35, "bounce": 1.4, "label": "Tugboat",
	},
	"airboat": {
		"length": 5.0, "width": 3.0, "mass": 700.0, "draft": 0.25,
		"thrust": 9500.0, "max_speed": 28.0, "steer_torque": 1.0, "rudder_lift": 0.14, "max_yaw": 1.4,
		"drag_long": 0.04, "drag_lat": 0.3, "planing": 0.9, "roll": 0.35, "bounce": 1.1, "label": "Airboat",
	},
	"towboat": {
		"length": 7.0, "width": 3.0, "mass": 1900.0, "draft": 0.5,
		"thrust": 23000.0, "max_speed": 31.0, "steer_torque": 0.65, "rudder_lift": 0.3, "max_yaw": 1.0,
		"drag_long": 0.05, "drag_lat": 1.5, "planing": 0.8, "roll": 1.0, "bounce": 1.0, "label": "Tow Boat",
	},
	"rowboat": {
		"length": 3.2, "width": 1.5, "mass": 220.0, "draft": 0.22,
		"thrust": 950.0, "max_speed": 3.9, "steer_torque": 2.0, "rudder_lift": 0.3, "max_yaw": 1.1,
		"drag_long": 0.28, "drag_lat": 1.6, "planing": 0.0, "roll": 0.6, "bounce": 0.6, "label": "Rowboat",
	},
	"sub": {
		"length": 7.5, "width": 2.0, "mass": 5000.0, "draft": 1.0, "radius": 1.0,
		"thrust": 20000.0, "max_speed": 13.0, "steer_torque": 0.8, "rudder_lift": 0.5, "max_yaw": 0.7,
		"drag_long": 0.06, "drag_lat": 2.0, "planing": 0.0, "roll": 0.3, "bounce": 0.5, "label": "Submarine",
	},
}

const COLORS := [
	Color(1.0, 0.48, 0.1), Color(0.2, 0.55, 1.0), Color(0.95, 0.25, 0.3), Color(0.3, 0.85, 0.4),
	Color(0.95, 0.85, 0.2), Color(0.7, 0.35, 0.9),
]


static func get_hull(id: String) -> Dictionary:
	return HULLS.get(id, HULLS.speedboat)
