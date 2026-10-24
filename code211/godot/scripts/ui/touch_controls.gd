class_name TouchControls
extends Control
## Мультитач-управление для iPhone.
##
## Почему не стандартные Button: в Godot кнопки получают только касание,
## эмулированное как мышь (первый палец). Здесь все касания обрабатываются
## вручную по индексу пальца — можно одновременно идти, крутить камеру и стрелять.
##
##   Левая часть экрана — плавающий джойстик (появляется под пальцем).
##   Правая часть — обзор свайпом.
##   Кнопки: ОГОНЬ (палец на кнопке огня тоже крутит камеру), перезарядка,
##   смена оружия, присед, пауза.

signal fire_pressed
signal reload_pressed
signal switch_pressed
signal crouch_pressed
signal pause_pressed

const JOY_RADIUS := 85.0
const DEAD_ZONE := 0.12

var active := true
var move_vector := Vector2.ZERO
var fire_held := false
var crouched := false
var weapon := 0

var _look_accum := Vector2.ZERO
var _joy_touch := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_touches: Dictionary = {}     # индекс пальца -> true
var _fire_touch := -1
var _buttons: Dictionary = {}          # имя -> {center: Vector2, radius: float}
var _pressed_flash: Dictionary = {}    # имя -> время подсветки
var _safe := Rect2()
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_layout)
	_layout()


func consume_look_delta() -> Vector2:
	var d := _look_accum
	_look_accum = Vector2.ZERO
	return d


func reset() -> void:
	move_vector = Vector2.ZERO
	fire_held = false
	_joy_touch = -1
	_fire_touch = -1
	_look_touches.clear()
	_look_accum = Vector2.ZERO
	queue_redraw()


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		reset()


func _layout() -> void:
	var size_v := get_viewport_rect().size
	_safe = UiKit.safe_rect(self)
	var r := _safe.end
	var s := clampf(size_v.y / 720.0, 0.75, 1.4)
	_buttons = {
		"fire": {"center": Vector2(r.x - 150 * s, r.y - 170 * s), "radius": 74.0 * s},
		"reload": {"center": Vector2(r.x - 300 * s, r.y - 95 * s), "radius": 44.0 * s},
		"switch": {"center": Vector2(r.x - 95 * s, r.y - 335 * s), "radius": 44.0 * s},
		"crouch": {"center": Vector2(r.x - 300 * s, r.y - 230 * s), "radius": 44.0 * s},
		"pause": {"center": Vector2(r.x - 48 * s, _safe.position.y + 48 * s), "radius": 34.0 * s},
	}
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_drag(sd.index, sd.position, sd.relative)
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, pos: Vector2) -> void:
	var btn := _button_at(pos)
	match btn:
		"fire":
			_fire_touch = idx
			fire_held = true
			_flash_btn("fire")
			fire_pressed.emit()
		"reload":
			_flash_btn(btn)
			reload_pressed.emit()
		"switch":
			_flash_btn(btn)
			switch_pressed.emit()
		"crouch":
			_flash_btn(btn)
			crouch_pressed.emit()
		"pause":
			_flash_btn(btn)
			pause_pressed.emit()
		_:
			var w := get_viewport_rect().size.x
			if pos.x < w * 0.42 and _joy_touch == -1:
				_joy_touch = idx
				var min_x := _safe.position.x + JOY_RADIUS
				_joy_origin = Vector2(maxf(pos.x, min_x), clampf(pos.y, _safe.position.y + JOY_RADIUS, _safe.end.y - JOY_RADIUS))
				_joy_pos = pos
				_update_joy()
			else:
				_look_touches[idx] = true
	queue_redraw()


func _touch_up(idx: int) -> void:
	if idx == _joy_touch:
		_joy_touch = -1
		move_vector = Vector2.ZERO
	if idx == _fire_touch:
		_fire_touch = -1
		fire_held = false
	_look_touches.erase(idx)
	queue_redraw()


func _touch_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _joy_touch:
		_joy_pos = pos
		_update_joy()
		queue_redraw()
	elif idx == _fire_touch or _look_touches.has(idx):
		_look_accum += rel


func _update_joy() -> void:
	var v := (_joy_pos - _joy_origin) / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	var m := v.length()
	if m < DEAD_ZONE:
		move_vector = Vector2.ZERO
	else:
		# Плавная кривая: точный шаг у центра, полная скорость у края.
		move_vector = v.normalized() * pow((m - DEAD_ZONE) / (1.0 - DEAD_ZONE), 1.3)


func _button_at(pos: Vector2) -> String:
	for b in _buttons:
		var info: Dictionary = _buttons[b]
		if pos.distance_to(info["center"]) <= float(info["radius"]) * 1.15:
			return b
	return ""


func _flash_btn(b: String) -> void:
	_pressed_flash[b] = 0.15


func _process(delta: float) -> void:
	var redraw := false
	for b in _pressed_flash.keys():
		_pressed_flash[b] -= delta
		redraw = true
		if _pressed_flash[b] <= 0.0:
			_pressed_flash.erase(b)
	if redraw:
		queue_redraw()


# ---------------------------------------------------------------- отрисовка

func _draw() -> void:
	if not active:
		return
	# Джойстик.
	if _joy_touch != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.08))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
		var knob := _joy_origin + move_vector.normalized() * minf((_joy_pos - _joy_origin).length(), JOY_RADIUS) if move_vector != Vector2.ZERO else _joy_pos
		if (knob - _joy_origin).length() > JOY_RADIUS:
			knob = _joy_origin + (knob - _joy_origin).normalized() * JOY_RADIUS
		draw_circle(knob, 34.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(_safe.position.x + 150, _safe.end.y - 150)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0, true)
		draw_circle(hint, 30.0, Color(1, 1, 1, 0.1))
	for b in _buttons:
		_draw_button(b)


func _draw_button(b: String) -> void:
	var info: Dictionary = _buttons[b]
	var c: Vector2 = info["center"]
	var r: float = info["radius"]
	var lit := _pressed_flash.has(b) or (b == "fire" and fire_held) or (b == "crouch" and crouched)
	var base := UiKit.AMBER if b == "fire" else Color(1, 1, 1)
	draw_circle(c, r, Color(base.r, base.g, base.b, 0.32 if lit else 0.16))
	draw_arc(c, r, 0, TAU, 48, Color(base.r, base.g, base.b, 0.8 if lit else 0.5), 3.0, true)
	var ink := Color(1, 1, 1, 0.92)
	match b:
		"fire":
			if weapon == 0:
				draw_arc(c, r * 0.38, 0, TAU, 32, ink, 3.0, true)
				for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(c + d * r * 0.18, c + d * r * 0.58, ink, 3.0, true)
			else:
				draw_line(c + Vector2(-r * 0.4, r * 0.4), c + Vector2(r * 0.35, -r * 0.35), ink, 7.0, true)
				draw_line(c + Vector2(-r * 0.15, r * 0.1), c + Vector2(-r * 0.05, r * 0.2), ink, 5.0, true)
		"reload":
			draw_arc(c, r * 0.45, -PI * 0.15, PI * 1.45, 24, ink, 3.5, true)
			var tip := c + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r * 0.45
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-9, -9), tip + Vector2(9, -4), tip + Vector2(-2, 9)]), ink)
		"switch":
			draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.32), Vector2(r * 0.7, r * 0.22)), ink)
			draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.14), Vector2(r * 0.18, r * 0.3)), ink)
			draw_line(c + Vector2(-r * 0.45, r * 0.42), c + Vector2(r * 0.5, r * 0.12), ink, 5.0, true)
		"crouch":
			var pts := PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.1), c + Vector2(0, r * 0.3), c + Vector2(r * 0.4, -r * 0.1)])
			draw_polyline(pts, ink, 4.5, true)
			draw_line(c + Vector2(-r * 0.4, -r * 0.35), c + Vector2(r * 0.4, -r * 0.35), ink, 3.0, true)
		"pause":
			draw_rect(Rect2(c + Vector2(-r * 0.32, -r * 0.4), Vector2(r * 0.22, r * 0.8)), ink)
			draw_rect(Rect2(c + Vector2(r * 0.1, -r * 0.4), Vector2(r * 0.22, r * 0.8)), ink)
