class_name UiKit
extends RefCounted
## Визуальный язык интерфейса «Код 211»: тёмно-синий «ночной патруль»,
## янтарный акцент (лента ограждения) и пара красный/синий из мигалок.
## Тема и фабрики виджетов строятся кодом — без .tres-файлов.

const INK := Color("0a0f17")
const PANEL := Color("111925")
const PANEL_2 := Color("192433")
const LINE := Color("2b3a4f")
const TEXT := Color("e9eef5")
const MUTED := Color("8796a8")
const AMBER := Color("ffb21e")
const RED := Color("ff3d4a")
const BLUE := Color("2e7dff")
const GREEN := Color("3ddc84")

const FONT_BODY := 24
const FONT_SMALL := 18
const FONT_TITLE := 64

static var _theme: Theme
static var _bold: Font
static var _regular: Font


static func font_regular() -> Font:
	if _regular == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["SF Pro Text", "Helvetica Neue", "Roboto", "Arial", "sans-serif"])
		f.font_weight = 500
		_regular = f
	return _regular


static func font_bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["SF Pro Display", "Helvetica Neue", "Roboto", "Arial", "sans-serif"])
		f.font_weight = 850
		_bold = f
	return _bold


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, bw: int = 0, pad: float = 14.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 4.0
	s.content_margin_right = pad + 4.0
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_regular()
	t.default_font_size = FONT_BODY
	t.set_stylebox("normal", "Button", box(PANEL_2, LINE, 10, 2))
	t.set_stylebox("hover", "Button", box(PANEL_2.lightened(0.06), AMBER.darkened(0.3), 10, 2))
	t.set_stylebox("pressed", "Button", box(AMBER.darkened(0.55), AMBER, 10, 2))
	t.set_stylebox("disabled", "Button", box(PANEL, LINE.darkened(0.3), 10, 2))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, AMBER, 10, 2))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_font("font", "Button", font_bold())
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 14, 2, 22.0))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 14, 2))
	# Слайдеры — толстые, под палец.
	var track := box(LINE, Color.TRANSPARENT, 6, 0, 0.0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(AMBER, Color.TRANSPARENT, 6, 0, 0.0)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_tex(30, TEXT))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(30, AMBER))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_2, LINE))
	_theme = t
	return t


static func _circle_tex(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold())
	return l


static func button(text: String, primary: bool = false, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", box(AMBER, AMBER, 10, 2))
		b.add_theme_stylebox_override("hover", box(AMBER.lightened(0.1), AMBER.lightened(0.1), 10, 2))
		b.add_theme_stylebox_override("pressed", box(AMBER.darkened(0.2), AMBER, 10, 2))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	b.pressed.connect(func(): Sfx.play("ui_click", -4.0, 0.0))
	return b


static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Безопасная область экрана (вырез «чёлки», домашний индикатор) в координатах вьюпорта.
static func safe_rect(c: CanvasItem) -> Rect2:
	var vp := c.get_viewport_rect()
	var os_name := OS.get_name()
	if os_name != "iOS" and os_name != "Android":
		return vp.grow(-16.0)
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return vp.grow(-16.0)
	var sx := vp.size.x / float(win.x)
	var sy := vp.size.y / float(win.y)
	var r := Rect2(Vector2(safe.position) * Vector2(sx, sy), Vector2(safe.size) * Vector2(sx, sy))
	return r.grow(-8.0)


## Полоса «ленты ограждения» — фирменный элемент меню.
static func tape(width: float) -> Control:
	var c := TapeStrip.new()
	c.custom_minimum_size = Vector2(width, 18)
	return c


class TapeStrip extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.AMBER)
		var x := -size.y
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + size.y * 0.8, 0),
				Vector2(x + size.y * 1.5, 0), Vector2(x + size.y * 0.7, size.y)]), UiKit.INK)
			x += size.y * 2.0
