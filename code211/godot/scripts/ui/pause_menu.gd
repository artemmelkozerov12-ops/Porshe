class_name PauseMenu
extends Control
## Меню паузы. Работает при get_tree().paused = true (process_mode ALWAYS у слоя).

signal resume_pressed
signal restart_pressed
signal menu_pressed

var _main: PanelContainer
var _settings: SettingsPanel
var _confirm_box: VBoxContainer
var _confirm_action := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_main = PanelContainer.new()
	_main.custom_minimum_size = Vector2(460, 0)
	center.add_child(_main)
	var v := UiKit.vbox(14)
	_main.add_child(v)
	v.add_child(UiKit.label("ПАУЗА", 40, UiKit.TEXT, true))
	v.add_child(UiKit.tape(410))
	var b_resume := UiKit.button("Продолжить", true)
	b_resume.pressed.connect(func(): resume_pressed.emit())
	v.add_child(b_resume)
	var b_restart := UiKit.button("Начать заново")
	b_restart.pressed.connect(func(): _ask("restart"))
	v.add_child(b_restart)
	var b_settings := UiKit.button("Настройки")
	b_settings.pressed.connect(_open_settings)
	v.add_child(b_settings)
	var b_menu := UiKit.button("Выйти в меню")
	b_menu.pressed.connect(func(): _ask("menu"))
	v.add_child(b_menu)
	_confirm_box = UiKit.vbox(10)
	_confirm_box.visible = false
	v.add_child(_confirm_box)
	_settings = SettingsPanel.new()
	_settings.visible = false
	center.add_child(_settings)
	_settings.closed.connect(func():
		_settings.visible = false
		_main.visible = true)


func open() -> void:
	visible = true
	_main.visible = true
	_settings.visible = false
	_confirm_box.visible = false


func _open_settings() -> void:
	_main.visible = false
	_settings.visible = true


## Подтверждение внутри панели (системные диалоги на iOS не используем).
func _ask(action: String) -> void:
	_confirm_action = action
	for c in _confirm_box.get_children():
		c.queue_free()
	var q := UiKit.label("Прогресс миссии будет потерян. Продолжить?", 20, UiKit.MUTED)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(400, 0)
	_confirm_box.add_child(q)
	var h := UiKit.hbox(10)
	var yes := UiKit.button("Да", true, 180)
	yes.pressed.connect(func():
		if _confirm_action == "restart":
			restart_pressed.emit()
		else:
			menu_pressed.emit())
	var no := UiKit.button("Отмена", false, 180)
	no.pressed.connect(func(): _confirm_box.visible = false)
	h.add_child(yes)
	h.add_child(no)
	_confirm_box.add_child(h)
	_confirm_box.visible = true
