class_name Quality
extends RefCounted
## Quality presets shared by the ocean, sky and (later) the rest of the game.
## Ocean.set_quality(name) applies the ocean/sky parts; Main may apply `msaa`/`scale` globally.
##
## | preset | FFT  | cascades | clipmap | shadows | extras                              |
## | low    | 128  | 2        | low     | off     | no SSR, no glow, no clouds          |
## | medium | 256  | 3        | medium  | 1       | glow, clouds (Intel UHD 60 fps target) |
## | high   | 512  | 3        | high    | 2       | SSR                                 |
## | ultra  | 1024 | 3        | high    | 4       | SSR, volumetric fog, SDFGI          |

const PRESETS := {
	"low": {
		"fft": 128, "cascades": 2, "clipmap": "low", "shadows": 0,
		"ssr": false, "glow": false, "volumetric": false, "sdfgi": false,
		"clouds": false, "rain": 500, "spray": false, "bicubic": false, "radiance": 64, "msaa": 0, "scale": 0.85,
	},
	"medium": {
		"fft": 256, "cascades": 3, "clipmap": "medium", "shadows": 1,
		"ssr": false, "glow": true, "volumetric": false, "sdfgi": false,
		"clouds": true, "rain": 1400, "spray": false, "bicubic": true, "radiance": 128, "msaa": 1, "scale": 1.0,
	},
	"high": {
		"fft": 512, "cascades": 3, "clipmap": "high", "shadows": 2,
		"ssr": true, "glow": true, "volumetric": false, "sdfgi": false,
		"clouds": true, "rain": 3000, "spray": true, "bicubic": true, "radiance": 256, "msaa": 2, "scale": 1.0,
	},
	"ultra": {
		"fft": 1024, "cascades": 3, "clipmap": "high", "shadows": 4,
		"ssr": true, "glow": true, "volumetric": true, "sdfgi": true,
		"clouds": true, "rain": 5000, "spray": true, "bicubic": true, "radiance": 256, "msaa": 2, "scale": 1.0,
	},
}

## Clipmap geometry: finest cell (m), cells per side of the centre block, number of rings (each doubles).
const CLIPMAPS := {
	"low": {"cell": 1.0, "block": 64, "rings": 9},
	"medium": {"cell": 0.6, "block": 96, "rings": 9},
	"high": {"cell": 0.4, "block": 128, "rings": 9},
}

static var current := "medium"


static func get_preset(name: String) -> Dictionary:
	if PRESETS.has(name):
		return PRESETS[name]
	push_warning("Quality: unknown preset '%s', using medium" % name)
	return PRESETS["medium"]


static func names() -> Array:
	return ["low", "medium", "high", "ultra"]


## Applies the viewport-level parts of a preset (MSAA, render scale). The ocean/sky parts are applied by Ocean.set_quality.
static func apply_viewport(viewport: Viewport, name: String) -> void:
	var p := get_preset(name)
	current = name
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][mini(int(p.msaa), 2)] as Viewport.MSAA
	viewport.scaling_3d_scale = float(p.scale)
