class_name Hud
extends Control
## Игровой HUD: здоровье, патроны, цели, прицел с разбросом, хитмаркер,
## индикатор направления урона, виньетка при низком здоровье, лента событий,
## а также «киношный» режим для вступительного ролика (полосы, субтитры, «Пропустить»).

signal skip_requested

var player: Node
var _hp := 100.0
var _hp_max := 100.0
var _hp_shown := 100.0
var _hit_t := 0.0
var _hit_kill := false
var _damage_marks: Array = []          # [{angle: float, t: float}]
var _reload := -1.0
var _cinematic := false
var _bars := 0.0
var _safe := Rect2()

var _ammo_lbl: Label
var _weapon_lbl: Label
var _obj_title: Label
var _obj_lines: Label
var _timer_lbl: Label
var _center_msg: Label
var _feed: VBoxContainer
var _subtitle: Label
var _caption: Label
var _skip_btn: Button
var _msg_t := 0.0
var _vignette: TextureRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.texture = _vignette_tex()
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.modulate = Color(1, 1, 1, 0)
	add_child(_vignette)

	_ammo_lbl = UiKit.label("17 / 85", 40, UiKit.TEXT, true)
	_ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ammo_lbl)
	_weapon_lbl = UiKit.label("ПИСТОЛЕТ", UiKit.FONT_SMALL, UiKit.MUTED, true)
	_weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_weapon_lbl)
	_obj_title = UiKit.label("ЗАДАЧА", 16, UiKit.AMBER, true)
	_obj_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_obj_title)
	_obj_lines = UiKit.label("", 22, UiKit.TEXT)
	_obj_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_obj_lines)
	_timer_lbl = UiKit.label("00:00", 18, UiKit.MUTED, true)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_timer_lbl)
	_center_msg = UiKit.label("", 30, UiKit.AMBER, true)
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_msg.modulate.a = 0.0
	add_child(_center_msg)
	_feed = UiKit.vbox(4)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_feed)
	_subtitle = UiKit.label("", 28, UiKit.TEXT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_subtitle.add_theme_constant_override("outline_size", 6)
	add_child(_subtitle)
	_caption = UiKit.label("", 22, UiKit.AMBER, true)
	add_child(_caption)
	_skip_btn = UiKit.button("Пропустить ›")
	_skip_btn.custom_minimum_size = Vector2(200, 56)
	_skip_btn.pressed.connect(func(): skip_requested.emit())
	add_child(_skip_btn)
	# Обводка: текст читается и на светлом потолке, и на тёмной улице.
	for l in [_ammo_lbl, _weapon_lbl, _obj_title, _obj_lines, _timer_lbl, _center_msg, _caption]:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("outline_size", 6)
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_cinematic(false)


func bind_player(p: Node) -> void:
	player = p
	p.health_changed.connect(_on_health)
	p.ammo_changed.connect(_on_ammo)
	p.weapon_changed.connect(_on_weapon)
	p.damaged.connect(_on_damaged)
	p.hit_confirmed.connect(_on_hit)
	p.reload_progress.connect(func(v: float): _reload = v)
	_on_health(p.hp, p.max_hp)
	_on_ammo(p.mag, p.reserve)
	_on_weapon(p.weapon)


func _layout() -> void:
	_safe = UiKit.safe_rect(self)
	var s := _safe
	var w := get_viewport_rect().size.x
	_ammo_lbl.position = Vector2(s.end.x - 360, s.position.y + 86)
	_ammo_lbl.size = Vector2(300, 48)
	_weapon_lbl.position = Vector2(s.end.x - 360, s.position.y + 132)
	_weapon_lbl.size = Vector2(300, 24)
	_obj_title.position = Vector2(w / 2.0 - 300, s.position.y + 4)
	_obj_title.size = Vector2(600, 20)
	_obj_lines.position = Vector2(w / 2.0 - 300, s.position.y + 24)
	_obj_lines.size = Vector2(600, 60)
	_timer_lbl.position = Vector2(s.position.x + 4, s.position.y + 44)
	_timer_lbl.size = Vector2(200, 24)
	_center_msg.position = Vector2(w / 2.0 - 400, get_viewport_rect().size.y * 0.3)
	_center_msg.size = Vector2(800, 44)
	_feed.position = Vector2(s.end.x - 320, s.position.y + 170)
	_feed.size = Vector2(300, 200)
	_subtitle.position = Vector2(w / 2.0 - 520, get_viewport_rect().size.y - 150)
	_subtitle.size = Vector2(1040, 80)
	_caption.position = Vector2(s.position.x + 24, 92)
	_caption.size = Vector2(700, 32)
	_skip_btn.position = Vector2(s.end.x - 216, s.position.y + 4)
	queue_redraw()


# ---------------------------------------------------------------- публичное

func set_objectives(lines: String) -> void:
	_obj_lines.text = lines


func set_timer(seconds: float) -> void:
	_timer_lbl.text = "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func flash_message(text: String, color: Color = UiKit.AMBER, duration: float = 1.6) -> void:
	_center_msg.text = text
	_center_msg.add_theme_color_override("font_color", color)
	_msg_t = duration


func feed(text: String, color: Color = UiKit.TEXT) -> void:
	var l := UiKit.label(text, 20, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	_feed.add_child(l)
	_feed.move_child(l, 0)
	while _feed.get_child_count() > 4:
		var last := _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(last)
		last.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func set_cinematic(on: bool) -> void:
	_cinematic = on
	for c in [_ammo_lbl, _weapon_lbl, _obj_title, _obj_lines, _timer_lbl, _feed]:
		c.visible = not on
	_skip_btn.visible = on
	_subtitle.visible = on
	_caption.visible = on
	if not on:
		_subtitle.text = ""
		_caption.text = ""
	queue_redraw()


func set_subtitle(text: String) -> void:
	_subtitle.text = text


func set_caption(text: String) -> void:
	_caption.text = text


# ---------------------------------------------------------------- события игрока

func _on_health(hp: float, max_hp: float) -> void:
	_hp = hp
	_hp_max = max_hp


func _on_ammo(mag: int, reserve: int) -> void:
	_ammo_lbl.text = "%d / %d" % [mag, reserve]
	_ammo_lbl.add_theme_color_override("font_color", UiKit.RED if mag <= 3 else UiKit.TEXT)


func _on_weapon(index: int) -> void:
	_weapon_lbl.text = "ПИСТОЛЕТ · 9 мм" if index == 0 else "ДУБИНКА · удар оглушает, второй — арест"
	_ammo_lbl.visible = index == 0 and not _cinematic


func _on_damaged(from_pos: Vector3) -> void:
	if player == null:
		return
	var to: Vector3 = from_pos - player.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	var right: Vector3 = player.global_transform.basis.x
	var ang := atan2(to.dot(right), to.dot(fwd))
	_damage_marks.append({"angle": ang, "t": 1.2})


func _on_hit(kill: bool, headshot: bool, arrest: bool) -> void:
	_hit_t = 0.25
	_hit_kill = kill or arrest
	if headshot and not kill:
		feed("В голову", UiKit.AMBER)


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	_hp_shown = move_toward(_hp_shown, _hp, delta * 80.0)
	_hit_t = maxf(0.0, _hit_t - delta)
	for m in _damage_marks:
		m["t"] -= delta
	_damage_marks = _damage_marks.filter(func(m): return m["t"] > 0.0)
	_bars = move_toward(_bars, 1.0 if _cinematic else 0.0, delta * 2.5)
	if _msg_t > 0.0:
		_msg_t -= delta
		_center_msg.modulate.a = clampf(_msg_t / 0.3, 0.0, 1.0)
	else:
		_center_msg.modulate.a = 0.0
	var low := clampf(1.0 - _hp / (_hp_max * 0.4), 0.0, 1.0) if _hp > 0.0 else 1.0
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
	_vignette.modulate.a = low * pulse * 0.85
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var c := vp / 2.0
	# Кинорежим: полосы сверху и снизу.
	if _bars > 0.0:
		var h := vp.y * 0.11 * _bars
		draw_rect(Rect2(0, 0, vp.x, h), Color(0, 0, 0, 0.95))
		draw_rect(Rect2(0, vp.y - h, vp.x, h), Color(0, 0, 0, 0.95))
	if _cinematic or player == null:
		return
	# Здоровье.
	var hx := _safe.position.x + 4
	var hy := _safe.position.y + 8
	draw_rect(Rect2(hx - 8, hy - 4, 276, 68), Color(0.02, 0.03, 0.05, 0.45))
	draw_string(UiKit.font_bold(), Vector2(hx, hy + 14), "ЗДОРОВЬЕ", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.TEXT)
	var bw := 260.0
	draw_rect(Rect2(hx, hy + 20, bw, 14), Color(1, 1, 1, 0.12))
	var k := clampf(_hp_shown / _hp_max, 0.0, 1.0)
	var col := UiKit.GREEN if k > 0.6 else (UiKit.AMBER if k > 0.3 else UiKit.RED)
	draw_rect(Rect2(hx, hy + 20, bw * k, 14), col)
	for i in range(1, 4):
		draw_line(Vector2(hx + bw * i / 4.0, hy + 20), Vector2(hx + bw * i / 4.0, hy + 34), Color(0, 0, 0, 0.5), 2.0)
	# Прицел: зазор растёт с разбросом.
	if player.alive:
		if player.weapon == 0:
			var gap := 8.0 + float(player.get_spread()) * 5.0
			var cc := Color(1, 1, 1, 0.9)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * gap, c + d * (gap + 11.0), Color(0, 0, 0, 0.5), 4.0)
				draw_line(c + d * gap, c + d * (gap + 11.0), cc, 2.0)
			draw_circle(c, 1.6, cc)
		else:
			draw_arc(c, 16.0, 0, TAU, 24, Color(1, 1, 1, 0.6), 2.0, true)
		if _reload >= 0.0:
			draw_arc(c, 28.0, -PI / 2.0, -PI / 2.0 + TAU * _reload, 40, UiKit.AMBER, 4.0, true)
	# Хитмаркер.
	if _hit_t > 0.0:
		var a := _hit_t / 0.25
		var hc := (UiKit.RED if _hit_kill else Color.WHITE)
		hc.a = a
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 8.0, c + d * 18.0, hc, 3.0, true)
	# Направление урона: красные дуги по окружности.
	for m in _damage_marks:
		var ang: float = m["angle"] - PI / 2.0
		var alpha := clampf(float(m["t"]) / 1.2, 0.0, 1.0)
		draw_arc(c, 130.0, ang - 0.35, ang + 0.35, 16, Color(UiKit.RED.r, UiKit.RED.g, UiKit.RED.b, alpha * 0.9), 8.0, true)


static func _vignette_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.6, 0.0, 0.0, 0.85))
	g.add_point(0.55, Color(0.6, 0.0, 0.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 256
	t.height = 256
	return t
