class_name MainMenu
extends Control
## Главное меню: заставка, «Играть», настройки, инструктаж (как играть).

signal play_pressed

var _panel: VBoxContainer
var _settings: SettingsPanel
var _howto: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.06, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var safe := UiKit.safe_rect(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(safe.position.x + 40))
	margin.add_theme_constant_override("margin_top", int(safe.position.y + 30))
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.add_theme_constant_override("margin_right", 40)
	add_child(margin)
	_panel = UiKit.vbox(14)
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(_panel)
	_panel.add_child(UiKit.label("ДЕЖУРНАЯ ЧАСТЬ · ВЫЗОВ", 18, UiKit.MUTED, true))
	var title := UiKit.label("КОД 211", 112, UiKit.TEXT, true)
	title.add_theme_constant_override("outline_size", 0)
	_panel.add_child(title)
	_panel.add_child(UiKit.label("Вооружённое ограбление. Вы — ближайший экипаж.", 24, UiKit.AMBER))
	_panel.add_child(UiKit.tape(520))
	var b_play := UiKit.button("Принять вызов", true, 420)
	b_play.pressed.connect(func(): play_pressed.emit())
	_panel.add_child(b_play)
	var b_how := UiKit.button("Инструктаж", false, 420)
	b_how.pressed.connect(func(): _show(_howto))
	_panel.add_child(b_how)
	var b_set := UiKit.button("Настройки", false, 420)
	b_set.pressed.connect(func(): _show(_settings))
	_panel.add_child(b_set)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _show(null))
	center.add_child(_settings)
	_howto = _build_howto()
	_howto.visible = false
	center.add_child(_howto)


func _show(p: Control) -> void:
	_panel.visible = p == null
	_settings.visible = p == _settings
	_howto.visible = p == _howto


func _build_howto() -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(820, 0)
	var v := UiKit.vbox(10)
	p.add_child(v)
	v.add_child(UiKit.label("ИНСТРУКТАЖ", 34, UiKit.TEXT, true))
	v.add_child(UiKit.tape(780))
	var lines := [
		["Движение", "Левая половина экрана — джойстик появляется под пальцем."],
		["Обзор", "Свайп по правой половине. Палец на кнопке огня тоже крутит камеру."],
		["Огонь", "Кнопка с прицелом. Удержание — повтор выстрелов."],
		["Оружие", "Пистолет: 17 патронов, отдача и разброс растут при частой стрельбе."],
		["Дубинка", "Подкрадитесь: первый удар оглушает, второй — арест (+250 очков)."],
		["Укрытия", "Пригнитесь (кнопка ▼) за стеллажом или кассой. Грабители делают так же."],
		["Важно", "Не заденьте кассира и покупателей — это провал операции."],
	]
	for l in lines:
		var h := UiKit.hbox(16)
		var k := UiKit.label(String(l[0]).to_upper(), 18, UiKit.AMBER, true)
		k.custom_minimum_size = Vector2(160, 0)
		h.add_child(k)
		var d := UiKit.label(String(l[1]), 21)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(600, 0)
		h.add_child(d)
		v.add_child(h)
	var ok := UiKit.button("Понятно", true, 220)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func(): _show(null))
	v.add_child(ok)
	return p
