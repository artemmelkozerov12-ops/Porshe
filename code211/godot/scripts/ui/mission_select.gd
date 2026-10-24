class_name MissionSelect
extends Control
## Выбор миссии (3 карточки) и сложности. Миссии открываются по порядку.

signal mission_chosen(index: int)
signal back_pressed

var _cards: HBoxContainer
var _diff_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.06, 0.7)
	add_child(shade)
	var safe := UiKit.safe_rect(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(safe.position.x + 30))
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", int(safe.position.y + 20))
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var v := UiKit.vbox(16)
	margin.add_child(v)
	var top := UiKit.hbox(16)
	v.add_child(top)
	var back := UiKit.button("‹ Назад", false, 160)
	back.pressed.connect(func(): back_pressed.emit())
	top.add_child(back)
	var title := UiKit.label("ВЫБОР ВЫЗОВА", 38, UiKit.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var dh := UiKit.hbox(6)
	top.add_child(dh)
	dh.add_child(UiKit.label("Сложность", 18, UiKit.MUTED, true))
	for i in 3:
		var b := UiKit.button(String(Settings.DIFFICULTY_NAMES[i]), false, 150)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 56)
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.AMBER, UiKit.AMBER, 10, 2))
		b.add_theme_color_override("font_pressed_color", UiKit.INK)
		var idx := i
		b.pressed.connect(func(): _set_difficulty(idx))
		dh.add_child(b)
		_diff_buttons.append(b)
	_set_difficulty(Settings.difficulty)
	_cards = UiKit.hbox(18)
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_cards)
	for i in MissionDB.count():
		_cards.add_child(_card(i))


func _set_difficulty(i: int) -> void:
	Settings.difficulty = i
	Settings.save_settings()
	for k in _diff_buttons.size():
		_diff_buttons[k].set_pressed_no_signal(k == i)


func _card(i: int) -> PanelContainer:
	var d := MissionDB.get_mission(i)
	var unlocked := i < Save.unlocked
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mood: String = d["mood"]
	var accent: Color = d["sign_color"]
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, accent if unlocked else UiKit.LINE, 14, 2, 18.0))
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label("ВЫЗОВ %d · %s" % [i + 1, {"day": "ДЕНЬ", "night": "НОЧЬ", "rain": "ВЕЧЕР, ДОЖДЬ"}.get(mood, "")], 15, accent if unlocked else UiKit.MUTED, true))
	v.add_child(UiKit.label(String(d["title"]), 30, UiKit.TEXT if unlocked else UiKit.MUTED, true))
	v.add_child(UiKit.label(String(d["caption"]), 18, UiKit.MUTED))
	var brief := UiKit.label(String(d["brief"]), 19, UiKit.TEXT if unlocked else UiKit.MUTED)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brief.custom_minimum_size = Vector2(260, 0)
	v.add_child(brief)
	var armor_counts := {"light": 0, "medium": 0, "heavy": 0}
	for b in d["bandits"]:
		armor_counts[b["armor"]] += 1
	var threat := "Грабителей: %d" % d["bandits"].size()
	var parts := []
	if armor_counts["medium"] > 0:
		parts.append("в бронежилетах: %d" % armor_counts["medium"])
	if armor_counts["heavy"] > 0:
		parts.append("тяжёлая броня: %d" % armor_counts["heavy"])
	if parts.size() > 0:
		threat += " (" + ", ".join(parts) + ")"
	v.add_child(UiKit.label(threat, 17, UiKit.MUTED))
	var best := Save.best_for(String(d["id"]))
	if not best.is_empty():
		var stars := ""
		for s in 3:
			stars += "★" if s < int(best.get("stars", 0)) else "☆"
		v.add_child(UiKit.label("%s  %s · %d" % [stars, String(best.get("grade", "")), int(best.get("score", 0))], 20, UiKit.AMBER, true))
	var b := UiKit.button("Выехать" if unlocked else "Закрыто", unlocked)
	b.disabled = not unlocked
	b.pressed.connect(func(): mission_chosen.emit(i))
	v.add_child(b)
	return p
