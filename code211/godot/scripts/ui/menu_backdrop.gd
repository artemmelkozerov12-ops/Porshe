class_name MenuBackdrop
extends Node3D
## Живой 3D-фон меню: ночная бодега, патрульная машина с мигалками, медленный облёт камеры.

var _cam: Camera3D
var _t := 0.0
var _center := Vector3.ZERO


func _ready() -> void:
	var def := MissionDB.get_mission(1)
	var builder := LevelBuilder.new()
	builder.build(self, def)
	var door: Vector3 = builder.door_positions()[0]
	_center = Vector3(door.x, 1.6, 1.0)
	var car := PoliceCar.new()
	add_child(car)
	car.global_position = Vector3(door.x + 3.2, 0, 6.2)
	car.rotation.y = -PI / 2.0 + 0.25
	car.set_lights(true)
	if car.door_pivot:
		car.door_pivot.rotation.y = deg_to_rad(-70.0)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true
	_update_cam()


func _process(delta: float) -> void:
	_t += delta
	_update_cam()


func _update_cam() -> void:
	var a := 0.35 + sin(_t * 0.08) * 0.35
	var pos := _center + Vector3(sin(a) * 11.0, 1.2 + sin(_t * 0.13) * 0.4, cos(a) * 11.0)
	_cam.global_position = pos
	_cam.look_at(_center + Vector3(-1.5, 0.2, 0), Vector3.UP)
