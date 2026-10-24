class_name PoliceCar
extends Node3D
## Патрульная машина: кузов, мигалки (красный/синий стробоскоп), открывающаяся дверь.
## Если есть res://assets/models/police_car.glb — используется он (с узлом "DoorPivot").

var door_pivot: Node3D
var lights_on := false
var _red: OmniLight3D
var _blue: OmniLight3D
var _red_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D
var _t := 0.0
var _wheels: Array[Node3D] = []


func _ready() -> void:
	if not _try_imported():
		_build()
	var body := StaticBody3D.new()
	body.collision_layer = Combat.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.45, 4.7)
	cs.shape = shape
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	add_child(body)
	_red = _light(Color(1.0, 0.1, 0.1), Vector3(-0.4, 1.6, 0.1))
	_blue = _light(Color(0.15, 0.35, 1.0), Vector3(0.4, 1.6, 0.1))
	set_lights(false)


func _process(delta: float) -> void:
	if not lights_on:
		return
	_t += delta
	# Паттерн «двойная вспышка»: красный, красный — синий, синий.
	var phase := fmod(_t, 0.8)
	var red_on := (phase < 0.08) or (phase > 0.16 and phase < 0.24)
	var blue_on := (phase > 0.4 and phase < 0.48) or (phase > 0.56 and phase < 0.64)
	_red.light_energy = 6.0 if red_on else 0.0
	_blue.light_energy = 6.0 if blue_on else 0.0
	if _red_mat:
		_red_mat.emission_energy_multiplier = 6.0 if red_on else 0.4
		_blue_mat.emission_energy_multiplier = 6.0 if blue_on else 0.4


func set_lights(on: bool) -> void:
	lights_on = on
	_red.visible = on
	_blue.visible = on
	if not on:
		if _red_mat:
			_red_mat.emission_energy_multiplier = 0.4
			_blue_mat.emission_energy_multiplier = 0.4


func spin_wheels(amount: float) -> void:
	for w in _wheels:
		w.rotate_object_local(Vector3.UP, amount)


func _light(c: Color, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 11.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	return l


func _try_imported() -> bool:
	var path := "res://assets/models/police_car.glb"
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var inst := scene.instantiate()
	add_child(inst)
	var d := inst.find_child("DoorPivot", true, false)
	door_pivot = d as Node3D
	if door_pivot == null:
		door_pivot = Node3D.new()
		add_child(door_pivot)
	return true


func _build() -> void:
	var L := Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR
	var white := Mats.solid(Color("eef0f2"), 0.35, 0.2)
	var black := Mats.solid(Color("121314"), 0.4, 0.2)
	var glass := Mats.solid(Color("0c1622"), 0.08, 0.5)
	Mats.add_mesh(self, Mats.box(Vector3(1.85, 0.55, 4.6)), white, Vector3(0, 0.62, 0), Vector3.ZERO, L)
	Mats.add_mesh(self, Mats.box(Vector3(1.87, 0.2, 4.62)), black, Vector3(0, 0.38, 0), Vector3.ZERO, L)
	Mats.add_mesh(self, Mats.box(Vector3(1.7, 0.06, 1.3)), black, Vector3(0, 0.92, -1.6), Vector3.ZERO, L)  # капот
	Mats.add_mesh(self, Mats.box(Vector3(1.7, 0.06, 0.9)), black, Vector3(0, 0.92, 1.85), Vector3.ZERO, L)  # багажник
	Mats.add_mesh(self, Mats.box(Vector3(1.62, 0.5, 2.3)), glass, Vector3(0, 1.15, 0.2), Vector3.ZERO, L)
	Mats.add_mesh(self, Mats.box(Vector3(1.5, 0.06, 2.1)), white, Vector3(0, 1.42, 0.25), Vector3.ZERO, L)  # крыша
	Mats.add_mesh(self, Mats.box(Vector3(1.2, 0.12, 0.3)), black, Vector3(0, 1.5, 0.1), Vector3.ZERO, L)
	_red_mat = StandardMaterial3D.new()
	_red_mat.albedo_color = Color(1.0, 0.1, 0.1)
	_red_mat.emission_enabled = true
	_red_mat.emission = Color(1.0, 0.1, 0.1)
	_blue_mat = StandardMaterial3D.new()
	_blue_mat.albedo_color = Color(0.15, 0.35, 1.0)
	_blue_mat.emission_enabled = true
	_blue_mat.emission = Color(0.15, 0.35, 1.0)
	Mats.add_mesh(self, Mats.box(Vector3(0.55, 0.1, 0.26)), _red_mat, Vector3(-0.3, 1.58, 0.1), Vector3.ZERO, L, false)
	Mats.add_mesh(self, Mats.box(Vector3(0.55, 0.1, 0.26)), _blue_mat, Vector3(0.3, 1.58, 0.1), Vector3.ZERO, L, false)
	# Фары и стопы.
	for sx in [-0.65, 0.65]:
		Mats.add_mesh(self, Mats.box(Vector3(0.3, 0.1, 0.04)), Mats.emissive(Color(1.0, 0.95, 0.8), 3.0), Vector3(sx, 0.7, -2.31), Vector3.ZERO, L, false)
		Mats.add_mesh(self, Mats.box(Vector3(0.3, 0.1, 0.04)), Mats.emissive(Color(0.9, 0.05, 0.05), 1.5), Vector3(sx, 0.72, 2.31), Vector3.ZERO, L, false)
	# Колёса.
	for wx in [-0.86, 0.86]:
		for wz in [-1.45, 1.45]:
			var hub := Node3D.new()
			hub.position = Vector3(wx, 0.34, wz)
			hub.rotation = Vector3(0, 0, PI / 2.0)
			add_child(hub)
			Mats.add_mesh(hub, Mats.cylinder(0.34, 0.24, 12), Mats.solid(Color("0d0d0d"), 0.9), Vector3.ZERO, Vector3.ZERO, L)
			Mats.add_mesh(hub, Mats.cylinder(0.2, 0.25, 8), Mats.solid(Color("8a8f96"), 0.3, 0.7), Vector3.ZERO, Vector3.ZERO, L, false)
			_wheels.append(hub)
	# Надписи по бортам.
	for side in [-1, 1]:
		var lbl := Label3D.new()
		lbl.text = "ПОЛИЦИЯ"
		lbl.font_size = 64
		lbl.pixel_size = 0.004
		lbl.modulate = Color("1f3b8f")
		lbl.outline_size = 0
		lbl.position = Vector3(0.94 * side, 0.62, 0.35)
		lbl.rotation = Vector3(0, PI / 2.0 * side, 0)
		lbl.layers = L
		add_child(lbl)
	# Водительская дверь (левая) на шарнире у передней кромки.
	door_pivot = Node3D.new()
	door_pivot.name = "DoorPivot"
	door_pivot.position = Vector3(-0.94, 0, -0.45)
	add_child(door_pivot)
	Mats.add_mesh(door_pivot, Mats.box(Vector3(0.06, 0.55, 1.1)), white, Vector3(0, 0.66, 0.55), Vector3.ZERO, L)
	Mats.add_mesh(door_pivot, Mats.box(Vector3(0.05, 0.42, 0.95)), glass, Vector3(0, 1.14, 0.55), Vector3.ZERO, L)
