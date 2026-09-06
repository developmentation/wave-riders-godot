class_name OceanPresets
extends RefCounted
## Per-world weather dictionaries for Ocean.set_weather(), ported from the web game's Worlds.js
## (sun angles converted from radians to degrees; water colours are the web's linear scatter
## reflectances expressed as sRGB Colors, which Ocean converts back to linear).
## Worlds.gd may reference these or carry its own copies with the same keys.

const WORLDS := {
	"hub": {
		"wind_speed": 3.2, "wind_dir_deg": 35.0, "swell_hs": 0.3, "swell_period": 9.0, "choppiness": 1.0,
		"foam": 0.35, "water_color": Color(0.21, 0.36, 0.40), "water_deep": Color(0.08, 0.17, 0.23),
		"sun_elev_deg": 9.7, "sun_azimuth_deg": 46.0, "cloud_cover": 0.32, "rain": 0.0, "fog": 0.03, "lightning_rate": 0.0,
	},
	"lagoon": {
		"wind_speed": 3.6, "wind_dir_deg": 20.0, "swell_hs": 0.45, "swell_period": 8.5, "choppiness": 1.0,
		"foam": 0.35, "water_color": Color(0.30, 0.62, 0.60), "water_deep": Color(0.10, 0.26, 0.28),
		"sun_elev_deg": 57.0, "sun_azimuth_deg": 212.0, "cloud_cover": 0.14, "rain": 0.0, "fog": 0.0, "lightning_rate": 0.0,
	},
	"swell": {
		"wind_speed": 6.5, "wind_dir_deg": 30.0, "swell_hs": 1.7, "swell_period": 13.0, "choppiness": 1.15,
		"foam": 1.0, "water_color": Color(0.14, 0.29, 0.36), "water_deep": Color(0.07, 0.16, 0.23),
		"sun_elev_deg": 41.0, "sun_azimuth_deg": 195.0, "cloud_cover": 0.30, "rain": 0.0, "fog": 0.03, "lightning_rate": 0.0,
	},
	"storm": {
		"wind_speed": 10.0, "wind_dir_deg": 60.0, "swell_hs": 2.2, "swell_period": 9.5, "choppiness": 1.3,
		"foam": 1.5, "water_color": Color(0.11, 0.24, 0.27), "water_deep": Color(0.06, 0.13, 0.17),
		"sun_elev_deg": 11.5, "sun_azimuth_deg": 172.0, "cloud_cover": 0.76, "rain": 0.9, "fog": 0.18, "lightning_rate": 0.6,
	},
	"giant": {
		"wind_speed": 5.5, "wind_dir_deg": 15.0, "swell_hs": 15.0, "swell_period": 16.0, "choppiness": 0.85,
		"foam": 0.8, "water_color": Color(0.11, 0.26, 0.38), "water_deep": Color(0.06, 0.14, 0.22),
		"sun_elev_deg": 51.6, "sun_azimuth_deg": 223.0, "cloud_cover": 0.18, "rain": 0.0, "fog": 0.02, "lightning_rate": 0.0,
	},
	"tempest": {
		"wind_speed": 23.0, "wind_dir_deg": 70.0, "swell_hs": 4.2, "swell_period": 11.5, "choppiness": 1.4,
		"foam": 1.1, "water_color": Color(0.17, 0.19, 0.33), "water_deep": Color(0.07, 0.09, 0.16),
		"sun_elev_deg": -6.9, "sun_azimuth_deg": 166.0, "cloud_cover": 0.8, "rain": 1.0, "fog": 0.5, "lightning_rate": 1.5,
	},
	"deep": {
		"wind_speed": 4.0, "wind_dir_deg": 20.0, "swell_hs": 0.6, "swell_period": 9.0, "choppiness": 1.0,
		"foam": 0.4, "water_color": Color(0.12, 0.28, 0.36), "water_deep": Color(0.05, 0.14, 0.22),
		"sun_elev_deg": 45.0, "sun_azimuth_deg": 200.0, "cloud_cover": 0.2, "rain": 0.0, "fog": 0.02, "lightning_rate": 0.0,
	},
}


static func get_weather(world_id: String) -> Dictionary:
	if WORLDS.has(world_id):
		return WORLDS[world_id].duplicate()
	return WORLDS["lagoon"].duplicate()
