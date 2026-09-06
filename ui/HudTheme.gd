class_name HudTheme
extends RefCounted
## Fonts, palette and label styling shared by the HUD (port of game.css variables and .wr-txt).
## Uses Godot's default font emboldened (rounded-bold look) with the system emoji font as a
## fallback so the boat/world emoji render in colour on Windows/macOS/Android.

const YELLOW := Color("ffd84d")
const ORANGE := Color("ff9f1a")
const BLUE := Color("0a7fbf")
const SKY := Color("3ec7ff")
const DEEP := Color("05324f")
const INK := Color("05324f")
const NAVY := Color(4.0 / 255.0, 30.0 / 255.0, 56.0 / 255.0, 0.82)
const GREEN := Color("46e07a")
const RED := Color("ff5d5d")
const PALE := Color("cfefff")

static var _font: FontVariation
static var _emoji: SystemFont
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		_emoji = SystemFont.new()
		_emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Segoe UI Symbol", "Noto Sans Symbols2"])
		# Godot's default font (Open Sans SemiBold) emboldened for the rounded-bold look; the
		# system emoji font fills in the boat/world glyphs.
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.6
		_font.fallbacks = [_emoji]
	return _font


static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = font()
		_theme.default_font_size = 24
		_theme.set_color("font_color", "Label", Color.WHITE)
		_theme.set_color("font_outline_color", "Label", INK)
		_theme.set_constant("outline_size", "Label", 4)
		var empty := StyleBoxEmpty.new()
		for cls in ["ScrollContainer", "PanelContainer", "Panel"]:
			_theme.set_stylebox("panel", cls, empty)
		_theme.set_stylebox("scroll", "HScrollBar", empty)
		_theme.set_stylebox("grabber", "HScrollBar", empty)
		_theme.set_stylebox("grabber_highlight", "HScrollBar", empty)
		_theme.set_stylebox("grabber_pressed", "HScrollBar", empty)
	return _theme


## Style a Label like .wr-txt: white, dark outline + offset shadow. `fs` in canvas pixels.
static func style_label(l: Label, fs: float, color := Color.WHITE, outline := true) -> void:
	var px := maxi(8, int(round(fs)))
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", maxi(2, int(round(fs * 0.11))))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(fs * 0.1))))
		l.add_theme_constant_override("shadow_outline_size", maxi(2, int(round(fs * 0.12))))
	else:
		l.add_theme_constant_override("outline_size", 0)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(fs * 0.07))))
		l.add_theme_constant_override("shadow_outline_size", maxi(1, int(round(fs * 0.08))))


static func make_label(text: String, fs: float, color := Color.WHITE, outline := true,
		halign := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(l, fs, color, outline)
	return l


## Text with outline + shadow drawn directly into a CanvasItem (buttons, badges, speedo).
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, fs: float, color: Color, outline_col := INK,
		outline := -1.0, halign := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0, shadow := true) -> void:
	var f := font()
	var px := maxi(6, int(round(fs)))
	var o := outline if outline >= 0.0 else fs * 0.09
	# draw_string only honours alignment when a width is given; centre/right-align manually.
	if width < 0.0 and halign != HORIZONTAL_ALIGNMENT_LEFT:
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		pos.x -= tw * (0.5 if halign == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
		halign = HORIZONTAL_ALIGNMENT_LEFT
	if shadow:
		f.draw_string_outline(ci.get_canvas_item(), pos + Vector2(0, fs * 0.1), text, halign, width, px, int(round(o + fs * 0.05)), Color(0, 0, 0, 0.35))
	if o > 0.0:
		f.draw_string_outline(ci.get_canvas_item(), pos, text, halign, width, px, int(round(o)), outline_col)
	f.draw_string(ci.get_canvas_item(), pos, text, halign, width, px, color)


static func text_width(text: String, fs: float) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(6, int(round(fs)))).x


## Baseline y so text of size fs is vertically centred on cy.
static func baseline(cy: float, fs: float) -> float:
	var f := font()
	var px := maxi(6, int(round(fs)))
	return cy + (f.get_ascent(px) - f.get_descent(px)) * 0.5


static func to_color(v: Variant, fallback := ORANGE) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.html(v) if Color.html_is_valid(v) else fallback
	if v is int:
		return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)
	if v is float:
		var i := int(v)
		return Color8((i >> 16) & 255, (i >> 8) & 255, i & 255)
	return fallback
