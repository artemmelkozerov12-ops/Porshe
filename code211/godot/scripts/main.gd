extends Node
## Корневой узел: переключает экраны (меню → выбор миссии → миссия) и
## гарантирует чистую смену состояния: снятие паузы, освобождение старой сцены,
## сброс захвата мыши и звуков.

var _screen: Node
var _backdrop: Node3D
var _ui_layer: CanvasLayer
var _mission_index := 0


func _ready() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 5
	add_child(_ui_layer)
	show_main_menu()


func _clear() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.stop_all()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null


func _ensure_backdrop() -> void:
	if _backdrop == null or not is_instance_valid(_backdrop):
		_backdrop = MenuBackdrop.new()
		add_child(_backdrop)


func _drop_backdrop() -> void:
	if _backdrop and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = null


func show_main_menu() -> void:
	_clear()
	_ensure_backdrop()
	var m := MainMenu.new()
	m.play_pressed.connect(show_mission_select)
	_ui_layer.add_child(m)
	_screen = m


func show_mission_select() -> void:
	_clear()
	_ensure_backdrop()
	var s := MissionSelect.new()
	s.mission_chosen.connect(start_mission)
	s.back_pressed.connect(show_main_menu)
	_ui_layer.add_child(s)
	_screen = s


func start_mission(index: int, skip_intro: bool = false) -> Mission:
	_clear()
	_drop_backdrop()
	_mission_index = clampi(index, 0, MissionDB.count() - 1)
	var mission := Mission.new()
	mission.setup(_mission_index, Settings.difficulty, skip_intro)
	mission.request_menu.connect(show_main_menu)
	mission.request_restart.connect(func(): start_mission(_mission_index, true))
	mission.request_next.connect(func(): start_mission(_mission_index + 1))
	add_child(mission)
	_screen = mission
	return mission


func current_screen() -> Node:
	return _screen
