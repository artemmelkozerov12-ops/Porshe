class_name ResultScreen
extends Control
## Экран итогов: вердикт, оценка (S/A/B/C), звёзды, статистика и разбор очков.

signal retry_pressed
signal next_pressed
signal menu_pressed

var _root: CenterContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_root = CenterContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)


func open(r: Dictionary, mdef: Dictionary, can_next: bool) -> void:
	for c in _root.get_children():
		c.queue_free()
	visible = true
	var won := bool(r["won"])
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	_root.add_child(panel)
	var v := UiKit.vbox(12)
	panel.add_child(v)

	var head := UiKit.hbox(24)
	v.add_child(head)
	var left := UiKit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	left.add_child(UiKit.label(String(mdef["title"]).to_upper() + " · " + String(Settings.DIFFICULTY_NAMES[Settings.difficulty]).to_upper(), 16, UiKit.MUTED, true))
	left.add_child(UiKit.label("УГРОЗА УСТРАНЕНА" if won else "ОПЕРАЦИЯ ПРОВАЛЕНА", 46, UiKit.GREEN if won else UiKit.RED, true))
	if not won:
		var reason := UiKit.label(String(r.get("reason", "")), 22, UiKit.TEXT)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(reason)
	else:
		var stars := ""
		for i in 3:
			stars += "★" if i < int(r["stars"]) else "☆"
		left.add_child(UiKit.label(stars + ("   НОВЫЙ РЕКОРД" if bool(r.get("record", false)) else ""), 34, UiKit.AMBER, true))
	var grade_box := UiKit.vbox(0)
	head.add_child(grade_box)
	grade_box.add_child(UiKit.label("ОЦЕНКА", 14, UiKit.MUTED, true))
	var grade := UiKit.label(String(r["grade"]), 96, UiKit.AMBER if won else UiKit.MUTED, true)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_box.add_child(grade)
	grade.pivot_offset = Vector2(40, 60)
	grade.scale = Vector2(1.6, 1.6)
	grade.modulate.a = 0.0
	var tw := grade.create_tween().set_parallel(true)
	tw.tween_property(grade, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(grade, "modulate:a", 1.0, 0.25)

	v.add_child(UiKit.tape(860))

	var cols := UiKit.hbox(40)
	v.add_child(cols)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	stats.add_theme_constant_override("v_separation", 6)
	cols.add_child(stats)
	var t := float(r["time"])
	_pair(stats, "Время", "%02d:%02d" % [int(t) / 60, int(t) % 60])
	_pair(stats, "Точность", "%d%%  (%d/%d)" % [roundi(float(r["accuracy"]) * 100.0), int(r["hits"]), int(r["shots"])])
	_pair(stats, "В голову", str(r["headshots"]))
	_pair(stats, "Нейтрализовано", str(r["kills"]))
	_pair(stats, "Арестовано", str(r["arrests"]))
	_pair(stats, "Получено урона", str(roundi(float(r["damage_taken"]))))
	if won:
		var pts := GridContainer.new()
		pts.columns = 2
		pts.add_theme_constant_override("h_separation", 24)
		pts.add_theme_constant_override("v_separation", 6)
		cols.add_child(pts)
		var names := {"neutralized": "Нейтрализация", "arrests": "Аресты", "headshots": "Точные попадания",
			"accuracy": "Точность", "time": "Скорость", "health": "Здоровье", "civilians": "Гражданские целы"}
		var bd: Dictionary = r["breakdown"]
		for k in names:
			_pair(pts, names[k], "+%d" % int(bd.get(k, 0)))
		_pair(pts, "Сложность", "×%.2f" % float(r["multiplier"]))
		_pair(pts, "ИТОГО", str(r["score"]), UiKit.AMBER)

	var buttons := UiKit.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(buttons)
	var b_menu := UiKit.button("В меню", false, 200)
	b_menu.pressed.connect(func(): menu_pressed.emit())
	buttons.add_child(b_menu)
	var b_retry := UiKit.button("Ещё раз", not (won and can_next), 200)
	b_retry.pressed.connect(func(): retry_pressed.emit())
	buttons.add_child(b_retry)
	if won and can_next:
		var b_next := UiKit.button("Следующая миссия ›", true, 300)
		b_next.pressed.connect(func(): next_pressed.emit())
		buttons.add_child(b_next)


func _pair(grid: GridContainer, title: String, value: String, color: Color = UiKit.TEXT) -> void:
	grid.add_child(UiKit.label(title, 20, UiKit.MUTED))
	var val := UiKit.label(value, 22, color, true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val)
