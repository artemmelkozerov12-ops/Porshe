class_name SettingsPanel
extends PanelContainer
## Панель настроек (из главного меню и из паузы).
## Сегментные переключатели вместо выпадающих списков — удобнее пальцем.

signal closed


func _ready() -> void:
	theme = UiKit.theme()
	custom_minimum_size = Vector2(760, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(720, 520)
	add_child(scroll)
	var v := UiKit.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UiKit.label("НАСТРОЙКИ", 34, UiKit.TEXT, true))
	v.add_child(UiKit.tape(700))

	v.add_child(_section("ГРАФИКА"))
	v.add_child(_row("Качество", _segmented(Settings.QUALITY_NAMES, Settings.quality, func(i):
		Settings.quality = i)))
	v.add_child(_row("Тени", _segmented(Settings.SHADOW_NAMES, Settings.shadow_quality, func(i):
		Settings.shadow_quality = i)))
	v.add_child(_row("Частота кадров", _segmented(["30 FPS", "60 FPS"], 0 if Settings.fps_cap == 30 else 1, func(i):
		Settings.fps_cap = 30 if i == 0 else 60)))
	var hint := UiKit.label("«Низкое» и 30 FPS заметно экономят батарею и снижают нагрев.", 17, UiKit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	v.add_child(_section("ЗВУК"))
	v.add_child(_row("Общая громкость", _slider(Settings.master_volume, 0.0, 1.0, func(x):
		Settings.master_volume = x)))
	v.add_child(_row("Музыка и фон", _slider(Settings.music_volume, 0.0, 1.0, func(x):
		Settings.music_volume = x)))
	v.add_child(_row("Эффекты", _slider(Settings.sfx_volume, 0.0, 1.0, func(x):
		Settings.sfx_volume = x)))

	v.add_child(_section("УПРАВЛЕНИЕ"))
	v.add_child(_row("Чувствительность", _slider(Settings.look_sensitivity, 0.3, 2.5, func(x):
		Settings.look_sensitivity = x)))
	v.add_child(_row("Помощь в прицеливании", _toggle(Settings.aim_assist, func(b):
		Settings.aim_assist = b)))
	v.add_child(_row("Инверсия по вертикали", _toggle(Settings.invert_y, func(b):
		Settings.invert_y = b)))

	var done := UiKit.button("Готово", true, 220)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(func():
		Settings.save_settings()
		closed.emit())
	v.add_child(done)


func _section(text: String) -> Label:
	var l := UiKit.label(text, 16, UiKit.AMBER, true)
	return l


func _row(title: String, control: Control) -> HBoxContainer:
	var h := UiKit.hbox(16)
	var l := UiKit.label(title, 22)
	l.custom_minimum_size = Vector2(260, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _segmented(options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var h := UiKit.hbox(6)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := UiKit.button(String(options[i]))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(130, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.AMBER, UiKit.AMBER, 10, 2))
		b.add_theme_color_override("font_pressed_color", UiKit.INK)
		var idx := i
		b.pressed.connect(func():
			on_pick.call(idx)
			Settings.apply())
		h.add_child(b)
	return h


func _slider(value: float, lo: float, hi: float, on_change: Callable) -> HBoxContainer:
	var h := UiKit.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(300, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UiKit.label("%d%%" % roundi(value / hi * 100.0), 20, UiKit.MUTED, true)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(x: float):
		on_change.call(x)
		val.text = "%d%%" % roundi(x / hi * 100.0)
		Settings.apply())
	h.add_child(s)
	h.add_child(val)
	return h


func _toggle(value: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.text = "Вкл" if value else "Выкл"
	c.toggled.connect(func(b: bool):
		on_change.call(b)
		c.text = "Вкл" if b else "Выкл"
		Sfx.play("ui_click", -4.0, 0.0))
	return c
