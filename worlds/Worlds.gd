class_name Worlds
extends RefCounted
## World definitions: port of src/game/Worlds.js. Same schema and values as the web game
## (keys in snake_case). Every world is built around the origin; gates are the equal-arc-length
## samples of the web's parametric loops (the exact numbers the web module computes at load).
##
## Coordinates: metres, +Z is heading 0, +X is heading +PI/2 (heading = atan2(dx, dz)).
##
## Weather: `weather.key` names a base preset in CONDITIONS, `weather.patch` overrides it;
## `world_weather(def)` merges them and `apply_world_weather(ocean, def)` maps the record to the
## Ocean.set_weather keys of docs/GODOT-PORT.md.

const DEG := PI / 180.0
const HUB_PORTAL_R := 135.0

## Base weather presets (src/ui/Sandbox.js CONDITIONS), angles in radians like the web.
const CONDITIONS := {
	"clear": {
		"wind_speed": 5.0, "gustiness": 0.15, "swell_hs": 1.1, "swell_period": 11.0, "choppiness": 1.1,
		"amplitude": 1.0, "spread": 0.6, "rain": 0.0, "storm": 0.0, "fog": 0.0, "spray": 0.0, "lightning_rate": 0.0,
		"turbidity": 2.0, "sun_elevation": 0.66, "sun_azimuth": 1.9, "sun_intensity": 26.0,
		"cloud_coverage": 0.12, "cloud_density": 0.35, "cloud_bottom": 1400.0, "cloud_top": 3000.0,
		"cloud_anvil": 0.0, "foam_strength": 0.7, "star_intensity": 0.0,
	},
	"trade": {
		"wind_speed": 10.5, "gustiness": 0.3, "swell_hs": 2.2, "swell_period": 10.5, "choppiness": 1.25,
		"amplitude": 1.0, "spread": 0.7, "rain": 0.0, "storm": 0.1, "fog": 0.05, "spray": 0.15, "lightning_rate": 0.0,
		"turbidity": 3.0, "sun_elevation": 0.72, "sun_azimuth": 2.1, "sun_intensity": 24.0,
		"cloud_coverage": 0.38, "cloud_density": 0.55, "cloud_bottom": 1100.0, "cloud_top": 3800.0,
		"cloud_anvil": 0.15, "foam_strength": 0.95, "star_intensity": 0.0,
	},
	"golden": {
		"wind_speed": 7.5, "gustiness": 0.2, "swell_hs": 2.8, "swell_period": 13.5, "choppiness": 1.15,
		"amplitude": 1.0, "spread": 0.5, "rain": 0.0, "storm": 0.05, "fog": 0.12, "spray": 0.1, "lightning_rate": 0.0,
		"turbidity": 4.5, "sun_elevation": 0.055, "sun_azimuth": 1.35, "sun_intensity": 20.0,
		"cloud_coverage": 0.34, "cloud_density": 0.6, "cloud_bottom": 1300.0, "cloud_top": 5200.0,
		"cloud_anvil": 0.3, "foam_strength": 0.9, "star_intensity": 0.2,
	},
	"overcast": {
		"wind_speed": 12.0, "gustiness": 0.35, "swell_hs": 3.0, "swell_period": 10.0, "choppiness": 1.3,
		"amplitude": 1.0, "spread": 0.8, "rain": 0.12, "storm": 0.3, "fog": 0.3, "spray": 0.3, "lightning_rate": 0.0,
		"turbidity": 5.0, "sun_elevation": 0.42, "sun_azimuth": 2.4, "sun_intensity": 18.0,
		"cloud_coverage": 0.68, "cloud_density": 0.9, "cloud_bottom": 700.0, "cloud_top": 3400.0,
		"cloud_anvil": 0.2, "foam_strength": 1.0, "star_intensity": 0.0,
	},
	"squall": {
		"wind_speed": 21.0, "gustiness": 0.55, "swell_hs": 5.0, "swell_period": 9.5, "choppiness": 1.35,
		"amplitude": 1.0, "spread": 0.85, "rain": 0.8, "storm": 0.75, "fog": 0.5, "spray": 0.9,
		"lightning_rate": 0.35, "turbidity": 6.0, "sun_elevation": 0.3, "sun_azimuth": 1.8, "sun_intensity": 16.0,
		"cloud_coverage": 0.7, "cloud_density": 1.0, "cloud_bottom": 800.0, "cloud_top": 5200.0,
		"cloud_anvil": 0.5, "foam_strength": 1.4, "star_intensity": 0.0,
	},
	"storm": {
		"wind_speed": 30.0, "gustiness": 0.7, "swell_hs": 9.0, "swell_period": 12.0, "choppiness": 1.4,
		"amplitude": 1.0, "spread": 0.9, "rain": 1.0, "storm": 1.0, "fog": 0.6, "spray": 1.4,
		"lightning_rate": 0.8, "turbidity": 6.5, "sun_elevation": 0.2, "sun_azimuth": 1.6, "sun_intensity": 14.0,
		"cloud_coverage": 0.74, "cloud_density": 1.1, "cloud_bottom": 620.0, "cloud_top": 5600.0,
		"cloud_anvil": 0.75, "foam_strength": 1.8, "star_intensity": 0.0,
	},
	"night": {
		"wind_speed": 26.0, "gustiness": 0.65, "swell_hs": 7.5, "swell_period": 11.5, "choppiness": 1.35,
		"amplitude": 1.0, "spread": 0.9, "rain": 0.85, "storm": 1.0, "fog": 0.5, "spray": 1.1,
		"lightning_rate": 1.4, "turbidity": 5.5, "sun_elevation": -0.22, "sun_azimuth": 1.5, "sun_intensity": 9.0,
		"cloud_coverage": 0.72, "cloud_density": 1.05, "cloud_bottom": 700.0, "cloud_top": 5000.0,
		"cloud_anvil": 0.6, "foam_strength": 1.5, "star_intensity": 1.0,
	},
}

## Defaults the web weather state carries and no world overrides (src/weather/Weather.js).
const WIND_ANGLE := 0.6
const SWELL_ANGLE := 1.1

const WORLDS := {
	"hub": {
		"id": "hub", "name": "Harbour", "icon": "anchor",
		"weather": {
			"key": "golden",
			"patch": {
				"wind_speed": 3.2, "gustiness": 0.1, "swell_hs": 0.3, "swell_period": 9.0, "choppiness": 1.0, "spread": 0.5,
				"rain": 0.0, "storm": 0.0, "fog": 0.03, "spray": 0.0, "lightning_rate": 0.0,
				"sun_elevation": 0.17, "sun_azimuth": 0.8, "sun_intensity": 22.0, "turbidity": 4.5,
				"cloud_coverage": 0.32, "cloud_density": 0.55, "cloud_bottom": 1300.0, "cloud_top": 4200.0, "cloud_anvil": 0.1,
				"foam_strength": 0.35, "star_intensity": 0.1,
			},
		},
		"water": {"scatter": [0.016, 0.066, 0.088], "absorb": [0.004, 0.020, 0.036]},
		"islands": [
			{"x": 0.0, "z": -205.0, "radius": 95.0, "height": 24.0, "seed": 11, "shape": "plateau", "palms": 26, "hut": true},
			{"x": -330.0, "z": 250.0, "radius": 70.0, "height": 22.0, "seed": 12, "palms": 18},
			{"x": 340.0, "z": 190.0, "radius": 58.0, "height": 18.0, "seed": 13, "palms": 14},
			{"x": 70.0, "z": 520.0, "radius": 120.0, "height": 42.0, "seed": 14, "palms": 36, "lighthouse": true},
			{"x": -180.0, "z": -420.0, "radius": 55.0, "height": 16.0, "seed": 15, "palms": 10},
		],
		"piers": [{"x": 0.0, "z": -110.0, "heading": 0.0, "length": 84.0, "width": 4.5}],
		"start": {"x": 0.0, "z": 0.0, "heading": 0.0},
		"gates": [],
		"laps": 0,
		# six rings on an arc 135 m out; easy worlds dead ahead, harder toward both ends
		"portals": [
			{"x": -130.4, "z": 34.9, "heading": -75.0 * DEG, "dest": "storm"},
			{"x": -95.5, "z": 95.5, "heading": -45.0 * DEG, "dest": "swell"},
			{"x": -34.9, "z": 130.4, "heading": -15.0 * DEG, "dest": "lagoon"},
			{"x": 34.9, "z": 130.4, "heading": 15.0 * DEG, "dest": "giant"},
			{"x": 95.5, "z": 95.5, "heading": 45.0 * DEG, "dest": "tempest"},
			{"x": 130.4, "z": 34.9, "heading": 75.0 * DEG, "dest": "deep"},
		],
		"bounds": 750.0,
	},
	"lagoon": {
		"id": "lagoon", "name": "Sunny Lagoon", "icon": "sun",
		"weather": {
			"key": "clear",
			"patch": {
				"wind_speed": 3.6, "gustiness": 0.1, "swell_hs": 0.45, "swell_period": 8.5, "choppiness": 1.0, "spread": 0.6,
				"rain": 0.0, "storm": 0.0, "fog": 0.0, "spray": 0.0, "lightning_rate": 0.0,
				"sun_elevation": 1.0, "sun_azimuth": 3.7, "sun_intensity": 26.0, "turbidity": 1.8,
				"cloud_coverage": 0.14, "cloud_density": 0.35, "cloud_bottom": 1600.0, "cloud_top": 2700.0, "cloud_anvil": 0.0,
				"foam_strength": 0.35,
			},
		},
		# green pushed up level with blue: turquoise enamel
		"water": {"scatter": [0.050, 0.200, 0.200], "absorb": [0.010, 0.042, 0.050]},
		"islands": [
			{"x": -112.0, "z": 4.0, "radius": 60.0, "height": 26.0, "seed": 21, "palms": 26},
			{"x": 112.0, "z": -18.0, "radius": 56.0, "height": 22.0, "seed": 22, "shape": "plateau", "palms": 34, "hut": true},
			{"x": -5.0, "z": 82.0, "radius": 34.0, "height": 13.0, "seed": 23, "palms": 12},
			# scenery outside the loop: something to look at from the start line and the horizon
			{"x": 390.0, "z": -310.0, "radius": 48.0, "height": 17.0, "seed": 24, "palms": 14, "scenery": true},
			{"x": -470.0, "z": 330.0, "radius": 60.0, "height": 21.0, "seed": 25, "palms": 16, "scenery": true},
			{"x": 620.0, "z": -110.0, "radius": 72.0, "height": 26.0, "seed": 26, "palms": 20, "scenery": true},
		],
		"start": {"x": 0.0, "z": -175.0, "heading": 1.571},
		# ellipse(0, 0, 270, 175), 8 gates, width 52
		"gates": [
			{"x": 87.7, "z": -165.5, "heading": 1.352, "width": 52.0},
			{"x": 239.3, "z": -81.0, "heading": 0.678, "width": 52.0},
			{"x": 239.3, "z": 81.0, "heading": -0.678, "width": 52.0},
			{"x": 87.7, "z": 165.5, "heading": -1.352, "width": 52.0},
			{"x": -87.7, "z": 165.5, "heading": -1.79, "width": 52.0},
			{"x": -239.3, "z": 81.0, "heading": -2.463, "width": 52.0},
			{"x": -239.3, "z": -81.0, "heading": 2.463, "width": 52.0},
			{"x": -87.7, "z": -165.5, "heading": 1.79, "width": 52.0},
		],
		"lap_length": 1414.0,
		"laps": 3,
		"portals": [{"x": -70.0, "z": -250.0, "heading": PI, "dest": "hub"}],
		"bounds": 900.0,
	},
	"swell": {
		"id": "swell", "name": "Rolling Swell", "icon": "wave",
		"weather": {
			"key": "trade",
			"patch": {
				"wind_speed": 6.5, "gustiness": 0.25, "swell_hs": 1.7, "swell_period": 13.0, "choppiness": 1.15, "spread": 0.55,
				"rain": 0.0, "storm": 0.05, "fog": 0.03, "spray": 0.15, "lightning_rate": 0.0,
				"sun_elevation": 0.72, "sun_azimuth": 3.4, "sun_intensity": 24.0, "turbidity": 2.4,
				"cloud_coverage": 0.30, "cloud_density": 0.9, "cloud_bottom": 1200.0, "cloud_top": 2800.0, "cloud_anvil": 0.0,
				"foam_strength": 1.0,
			},
		},
		"water": {"scatter": [0.014, 0.062, 0.100], "absorb": [0.004, 0.020, 0.040]},
		"islands": [
			{"x": -185.0, "z": 0.0, "radius": 76.0, "height": 44.0, "seed": 31, "palms": 30},
			{"x": 185.0, "z": 0.0, "radius": 68.0, "height": 38.0, "seed": 32, "shape": "plateau", "palms": 28, "lighthouse": true},
		],
		"start": {"x": 166.9, "z": 151.2, "heading": -2.116},
		# figure8(0, 0, 335, 350) shifted 0.167, 12 gates, width 42, crossing avoided (r 60)
		"gates": [
			{"x": 98.2, "z": 98.1, "heading": -2.306, "width": 42.0},
			{"x": -45.3, "z": -46.9, "heading": -2.364, "width": 42.0},
			{"x": -153.0, "z": -142.2, "heading": -2.171, "width": 42.0},
			{"x": -303.9, "z": -133.6, "heading": -0.557, "width": 42.0},
			{"x": -333.3, "z": 35.2, "heading": 0.098, "width": 42.0},
			{"x": -249.0, "z": 174.0, "heading": 1.408, "width": 42.0},
			{"x": -98.2, "z": 98.1, "heading": 2.306, "width": 42.0},
			{"x": 45.3, "z": -46.9, "heading": 2.364, "width": 42.0},
			{"x": 153.0, "z": -142.2, "heading": 2.171, "width": 42.0},
			{"x": 303.9, "z": -133.6, "heading": 0.557, "width": 42.0},
			{"x": 333.3, "z": 35.2, "heading": -0.098, "width": 42.0},
			{"x": 249.0, "z": 174.0, "heading": -1.408, "width": 42.0},
		],
		"lap_length": 2088.0,
		"laps": 2,
		"portals": [{"x": 235.0, "z": 235.0, "heading": PI / 4.0, "dest": "hub"}],
		"bounds": 1000.0,
	},
	"storm": {
		"id": "storm", "name": "Storm Run", "icon": "lightning",
		"weather": {
			"key": "squall",
			"patch": {
				"wind_speed": 14.0, "gustiness": 0.5, "swell_hs": 4.5, "swell_period": 10.5, "choppiness": 1.3, "spread": 0.8,
				"rain": 0.9, "storm": 0.85, "fog": 0.18, "spray": 0.9, "lightning_rate": 0.6,
				"sun_elevation": 0.2, "sun_azimuth": 3.0, "sun_intensity": 14.0, "turbidity": 6.0,
				"cloud_coverage": 0.76, "cloud_density": 1.15, "cloud_bottom": 600.0, "cloud_top": 5200.0, "cloud_anvil": 0.6,
				"foam_strength": 1.5,
			},
		},
		# hold auto-exposure down so the squall reads dark
		"exposure": 0.7,
		"water": {"scatter": [0.010, 0.042, 0.052], "absorb": [0.003, 0.012, 0.022]},
		"islands": [
			# one big crescent wrapping the far side of the bay
			{"x": 0.0, "z": 60.0, "radius": 100.0, "height": 58.0, "seed": 41, "shape": "crescent", "palms": 40, "warp": 0.2, "detail": 0.1,
				"arc": {"r": 315.0, "a0": 22.0 * DEG, "a1": 158.0 * DEG, "thick": 72.0}},
			{"x": -340.0, "z": -130.0, "radius": 48.0, "height": 15.0, "seed": 42, "palms": 8},
			{"x": 350.0, "z": -140.0, "radius": 44.0, "height": 13.0, "seed": 43, "palms": 6},
		],
		"start": {"x": 0.0, "z": -65.0, "heading": 1.571},
		# ellipse(0, 60, 205, 125), 7 gates, width 36
		"gates": [
			{"x": 74.5, "z": -56.5, "heading": 1.337, "width": 36.0},
			{"x": 196.2, "z": 23.8, "heading": 0.46, "width": 36.0},
			{"x": 144.1, "z": 148.9, "heading": -1.029, "width": 36.0},
			{"x": 0.0, "z": 185.0, "heading": -1.571, "width": 36.0},
			{"x": -144.1, "z": 148.9, "heading": -2.113, "width": 36.0},
			{"x": -196.2, "z": 23.8, "heading": 2.681, "width": 36.0},
			{"x": -74.5, "z": -56.5, "heading": 1.804, "width": 36.0},
		],
		"lap_length": 1052.0,
		"laps": 2,
		"portals": [{"x": -95.0, "z": -150.0, "heading": PI, "dest": "hub"}],
		"bounds": 800.0,
	},
	"giant": {
		"id": "giant", "name": "Titan Swell", "icon": "giantwave",
		"weather": {
			"key": "clear",
			"patch": {
				# glassy between the rollers: one enormous long-period swell, Hs ~15 m, ~400 m wavelength
				"wind_speed": 5.5, "gustiness": 0.1, "swell_hs": 15.0, "swell_period": 16.0, "choppiness": 0.85, "spread": 0.35,
				"rain": 0.0, "storm": 0.0, "fog": 0.02, "spray": 0.25, "lightning_rate": 0.0,
				"sun_elevation": 0.9, "sun_azimuth": 3.9, "sun_intensity": 26.0, "turbidity": 1.6,
				"cloud_coverage": 0.18, "cloud_density": 0.4, "cloud_bottom": 1800.0, "cloud_top": 3000.0, "cloud_anvil": 0.0,
				"foam_strength": 0.8,
			},
		},
		# saturated deep blue: open-ocean scattering with the green held back
		"water": {"scatter": [0.010, 0.050, 0.112], "absorb": [0.003, 0.016, 0.034]},
		"islands": [
			# one tall spire in the middle of the oval, two big landmarks far outside it
			{"x": 0.0, "z": 0.0, "radius": 70.0, "height": 78.0, "seed": 51, "palms": 22, "hut": true},
			{"x": -1000.0, "z": 300.0, "radius": 115.0, "height": 92.0, "seed": 52, "palms": 34, "lighthouse": true},
			{"x": 1000.0, "z": -300.0, "radius": 105.0, "height": 84.0, "seed": 53, "shape": "plateau", "palms": 30},
		],
		"start": {"x": 0.0, "z": -380.0, "heading": 1.571},
		# ellipse(0, 0, 600, 380), 8 gates, width 32: one gate per roller
		"gates": [
			{"x": 193.4, "z": -359.7, "heading": 1.358, "width": 32.0},
			{"x": 530.3, "z": -177.7, "heading": 0.696, "width": 32.0},
			{"x": 530.3, "z": 177.7, "heading": -0.696, "width": 32.0},
			{"x": 193.4, "z": 359.7, "heading": -1.358, "width": 32.0},
			{"x": -193.4, "z": 359.7, "heading": -1.783, "width": 32.0},
			{"x": -530.3, "z": 177.7, "heading": -2.446, "width": 32.0},
			{"x": -530.3, "z": -177.7, "heading": 2.446, "width": 32.0},
			{"x": -193.4, "z": -359.7, "heading": 1.783, "width": 32.0},
		],
		"gate_spacing": [300.0, 450.0],
		"lap_length": 3118.0,
		"laps": 2,
		"portals": [{"x": -130.0, "z": -480.0, "heading": PI, "dest": "hub"}],
		"probe_span": 400.0,
		"bounds": 1400.0,
	},
	"tempest": {
		"id": "tempest", "name": "The Perfect Storm", "icon": "tempest",
		"weather": {
			"key": "storm",
			"patch": {
				# Beaufort 11 base; wind sea trimmed so the total integrates to Hs ~8 m
				"wind_speed": 28.0, "gustiness": 0.6, "swell_hs": 13.0, "swell_period": 14.5, "choppiness": 1.35, "spread": 0.9,
				"rain": 1.0, "storm": 1.0, "fog": 0.5, "spray": 1.4, "lightning_rate": 1.5,
				# sun just under the horizon: the sky is lit by the deck's own glow and the lightning
				"sun_elevation": -0.12, "sun_azimuth": 2.9, "sun_intensity": 6.0, "turbidity": 7.0,
				"cloud_coverage": 0.8, "cloud_density": 1.2, "cloud_bottom": 480.0, "cloud_top": 5600.0, "cloud_anvil": 0.8,
				"foam_strength": 1.1, "star_intensity": 0.35,
			},
		},
		"exposure": 0.6,
		# thunder purple: red lifted level with green so the water goes violet-black
		"water": {"scatter": [0.014, 0.018, 0.050], "absorb": [0.004, 0.011, 0.020]},
		"islands": [
			# a huge crescent wrapping the whole north side of the bay; steep shelf so an 8 m trough
			# over a long sandy shelf does not ground boats
			{"x": 0.0, "z": 80.0, "radius": 120.0, "height": 82.0, "seed": 61, "shape": "crescent", "palms": 40, "warp": 0.18, "detail": 0.1, "shelf": 0.6,
				"arc": {"r": 470.0, "a0": 20.0 * DEG, "a1": 160.0 * DEG, "thick": 90.0}},
			{"x": -430.0, "z": -230.0, "radius": 50.0, "height": 17.0, "seed": 62, "palms": 8},
			{"x": 440.0, "z": -270.0, "radius": 46.0, "height": 15.0, "seed": 63, "palms": 6},
		],
		"start": {"x": 0.0, "z": -110.0, "heading": 1.571},
		# ellipse(0, 40, 250, 150), 6 gates, width 36
		"gates": [
			{"x": 105.1, "z": -96.1, "heading": 1.3, "width": 36.0},
			{"x": 250.0, "z": 40.0, "heading": 0.0, "width": 36.0},
			{"x": 105.1, "z": 176.1, "heading": -1.3, "width": 36.0},
			{"x": -105.1, "z": 176.1, "heading": -1.842, "width": 36.0},
			{"x": -250.0, "z": 40.0, "heading": -3.142, "width": 36.0},
			{"x": -105.1, "z": -96.1, "heading": 1.842, "width": 36.0},
		],
		"lap_length": 1276.0,
		"laps": 2,
		"portals": [{"x": -110.0, "z": -230.0, "heading": PI, "dest": "hub"}],
		"probe_span": 300.0,
		"bounds": 850.0,
		# periodic drama driven by update_world_events(); times in seconds
		"events": {
			"rogue": {"first": 18.0, "every": [35.0, 50.0], "height": 14.0, "radius": 200.0, "wavelength": 320.0, "distance": 420.0},
			"spout": {"first": 30.0, "every": [75.0, 110.0], "strength": 20.0, "distance": [520.0, 720.0], "min_start_dist": 400.0},
			"lightning": {"first": 4.0, "every": [9.0, 16.0], "count": [4.0, 8.0], "radius": 1500.0},
		},
	},
}

## Portal destinations that live outside this file (the submarine world).
const EXTERNAL_DESTS := ["deep"]


# -------------------------------------------------------------- weather
## Full weather record for a world: preset + patch (+ water colour keys).
static func world_weather(def: Dictionary) -> Dictionary:
	var wk: String = def.weather.get("key", "clear")
	var base: Dictionary = CONDITIONS.get(wk, CONDITIONS.clear)
	var w := base.duplicate()
	w["wind_angle"] = WIND_ANGLE
	w["swell_angle"] = SWELL_ANGLE
	w.merge(def.weather.get("patch", {}), true)
	if def.has("water"):
		w["water_scatter"] = def.water.scatter
		w["water_absorb"] = def.water.absorb
	w["exposure"] = def.get("exposure", 1.0)
	return w


## Approximate colour of the water column from its scattering coefficients: the hue lives in the
## scatter vector (the absorption in these defs scales with it), the body stays dark like real
## deep water (the FFT ocean may use the raw `water_scatter` / `water_absorb` instead).
const WATER_GAIN := 1.6


static func water_color(def: Dictionary) -> Color:
	if not def.has("water"):
		return Color(0.02, 0.28, 0.42)
	var s: Array = def.water.scatter
	return Color(clampf(s[0] * WATER_GAIN, 0.0, 1.0), clampf(s[1] * WATER_GAIN, 0.0, 1.0), clampf(s[2] * WATER_GAIN, 0.0, 1.0))


## Map the web weather record onto Ocean.set_weather keys (docs/GODOT-PORT.md). Extra keys
## (gustiness, spread, storm, spray, cloud_density, ...) ride along for the sky module.
static func ocean_weather(def: Dictionary) -> Dictionary:
	var w := world_weather(def)
	var o := {
		"wind_speed": w.wind_speed,
		"wind_dir_deg": rad_to_deg(w.wind_angle),
		"swell_dir_deg": rad_to_deg(w.swell_angle),
		"swell_hs": w.swell_hs,
		"swell_period": w.swell_period,
		"choppiness": w.choppiness,
		"foam": w.foam_strength,
		"water_color": water_color(def),
		"sun_elev_deg": rad_to_deg(w.sun_elevation),
		"sun_azimuth_deg": rad_to_deg(w.sun_azimuth),
		"cloud_cover": w.cloud_coverage,
		"rain": w.rain,
		"fog": w.fog,
		"lightning_rate": w.lightning_rate,
	}
	for k in ["gustiness", "spread", "storm", "spray", "sun_intensity", "turbidity", "cloud_density",
			"cloud_bottom", "cloud_top", "cloud_anvil", "star_intensity", "amplitude", "exposure",
			"water_scatter", "water_absorb"]:
		if w.has(k):
			o[k] = w[k]
	return o


static func apply_world_weather(ocean: Node, def: Dictionary, immediate := false) -> void:
	if ocean == null or not ocean.has_method("set_weather"):
		return
	ocean.set_weather(ocean_weather(def), immediate)


# --------------------------------------------------------------- events
## Per-world scripted drama (rogue waves, distant waterspouts, lightning bursts) on top of the
## ambient weather. Call `update_world_events(ocean, def, dt, focus)` every frame with the
## player's position (defaults to the current camera); state lives here keyed by def.id and
## is reset by `reset_world_events(id)` whenever the world is rebuilt.
##
## The ocean is asked via has_method so the stub (which has none of these) is fine:
##   spawn_rogue({x, z, angle, height, radius, wavelength, speed})
##   spawn_waterspout(x, z, strength)
##   lightning_burst(count, {cloud_base, radius, window})
static var event_rate := 1.0
static var _events := {}


static func reset_world_events(id := "") -> void:
	if id == "":
		_events.clear()
	else:
		_events.erase(id)


static func _pick(v) -> float:
	if v is Array:
		return randf_range(v[0], v[1])
	return float(v)


static func update_world_events(ocean: Node, def: Dictionary, dt: float, focus := Vector3.INF) -> void:
	if ocean == null or not def.has("events") or dt <= 0.0:
		return
	var ev: Dictionary = def.events
	var id: String = def.id
	if focus == Vector3.INF:
		var cam: Camera3D = ocean.get_viewport().get_camera_3d() if ocean.is_inside_tree() else null
		focus = cam.global_position if cam else Vector3.ZERO
	var st: Dictionary = _events.get(id, {})
	if st.is_empty():
		st = {"time": 0.0, "next": {}, "prev": focus, "vel": Vector3.ZERO}
		for k in ev.keys():
			var e: Dictionary = ev[k]
			st.next[k] = (float(e.first) if e.has("first") else _pick(e.every)) / event_rate
		_events[id] = st
	st.time += dt
	# smoothed velocity: rogue waves are aimed at where the boat is going (teleports ignored)
	var v: Vector3 = (focus - st.prev) / dt
	if v.length_squared() < 60.0 * 60.0:
		st.vel = st.vel.lerp(v, 1.0 - exp(-dt * 2.0))
	st.prev = focus
	var w := world_weather(def)
	for k in ev.keys():
		if st.time < st.next[k]:
			continue
		var e: Dictionary = ev[k]
		st.next[k] = st.time + _pick(e.every) / event_rate
		match k:
			"rogue":
				# form the group upwind-ish of the player and send it through where the boat will be
				var base: float = w.get("swell_angle", w.get("wind_angle", 1.0))
				var ang := base + randf_range(-0.9, 0.9)
				var dist: float = e.get("distance", 420.0)
				var wavelength: float = e.get("wavelength", 320.0)
				var speed := sqrt(9.81 * wavelength / TAU)
				var lead := minf(dist / speed * 0.5, 10.0)
				var tx: float = focus.x + st.vel.x * lead
				var tz: float = focus.z + st.vel.z * lead
				if ocean.has_method("spawn_rogue"):
					ocean.spawn_rogue({
						"x": tx - cos(ang) * dist, "z": tz - sin(ang) * dist, "angle": ang,
						"height": e.get("height", 14.0), "radius": e.get("radius", 200.0),
						"wavelength": wavelength, "speed": speed,
					})
			"spout":
				# a distant funnel: well away from the player and from the start line
				var s: Dictionary = def.get("start", {"x": 0.0, "z": 0.0})
				var x := 0.0
				var z := 0.0
				for tries in 8:
					var ang := randf() * TAU
					var d := _pick(e.get("distance", [520.0, 720.0]))
					x = focus.x + cos(ang) * d
					z = focus.z + sin(ang) * d
					if Vector2(x - s.x, z - s.z).length() >= float(e.get("min_start_dist", 400.0)):
						break
				if ocean.has_method("spawn_waterspout"):
					ocean.spawn_waterspout(x, z, e.get("strength", 20.0))
			"lightning":
				var n := int(round(_pick(e.get("count", 6.0))))
				if ocean.has_method("lightning_burst"):
					ocean.lightning_burst(n, {"cloud_base": w.get("cloud_bottom", 600.0), "radius": e.get("radius", 1500.0), "window": 2.5})


## Time-since-load / next-event snapshot for the harness.
static func event_state(id: String) -> Dictionary:
	return _events.get(id, {})
