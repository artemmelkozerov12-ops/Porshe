class_name Viewmodel
extends Node3D
## Оружие от первого лица: пистолет и дубинка в руках.
## Покачивание при ходьбе, инерция при повороте, отдача, перезарядка, удар дубинкой —
## всё процедурно (без отдельных клипов), поэтому отзывчиво и дёшево.

const REST_PISTOL := Vector3(0.17, -0.19, -0.38)
const REST_BATON := Vector3(0.2, -0.24, -0.42)

var pistol: Node3D
var baton: Node3D
var _slide: Node3D
var _mag: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t := 0.0
var _kick := 0.0
var _bob_t := 0.0
var _sway := Vector2.ZERO
var _active := 0
var _switch_t := 0.0
var _reload_t := -1.0
var _reload_dur := 1.0
var _swing_t := -1.0
const SWING_DUR := 0.42


func _ready() -> void:
	pistol = Node3D.new()
	pistol.name = "Pistol"
	add_child(pistol)
	baton = Node3D.new()
	baton.name = "Baton"
	add_child(baton)
	_build_pistol()
	_build_baton()
	baton.visible = false
	pistol.position = REST_PISTOL
	baton.position = REST_BATON


func _build_pistol() -> void:
	var L := Combat.VIS_INTERIOR | Combat.VIS_EXTERIOR
	var dark := Mats.solid(Color("1d1f23"), 0.45, 0.3)
	var grip_c := Mats.solid(Color("15161a"), 0.8)
	var sleeve := Mats.solid(Color("1f2d4d"), 0.85)
	var skin := Mats.solid(Color("c69c7b"), 0.7)
	var imported := _load_weapon_glb("pistol", ["Slide", "Mag"])
	if imported:
		pistol.add_child(imported)
		_slide = imported.find_child("Slide", true, false)
		_mag = imported.find_child("Mag", true, false)
		_add(pistol, Vector3(0.06, 0.07, 0.08), Vector3(0.012, -0.07, 0.05), skin)
	else:
		_slide = Node3D.new()
		pistol.add_child(_slide)
		_add(_slide, Vector3(0.034, 0.038, 0.2), Vector3(0, 0.025, -0.05), dark)
		_add(_slide, Vector3(0.006, 0.012, 0.01), Vector3(0, 0.05, -0.145), Mats.solid(Color("e8e8e8"), 0.3))   # мушка
		_add(_slide, Vector3(0.026, 0.01, 0.012), Vector3(0, 0.05, 0.035), dark)                               # целик
		_add(pistol, Vector3(0.03, 0.02, 0.17), Vector3(0, -0.003, -0.04), grip_c)                             # рамка
		var grip := Node3D.new()
		grip.rotation.x = deg_to_rad(-12)
		grip.position = Vector3(0, -0.06, 0.03)
		pistol.add_child(grip)
		_add(grip, Vector3(0.032, 0.11, 0.045), Vector3.ZERO, grip_c)
		_mag = Node3D.new()
		grip.add_child(_mag)
		_add(_mag, Vector3(0.026, 0.02, 0.038), Vector3(0, -0.062, 0), dark)
		_add(grip, Vector3(0.06, 0.07, 0.08), Vector3(0.012, -0.01, 0.02), skin)
	# Вторая кисть и рукава.
	_add(pistol, Vector3(0.055, 0.06, 0.075), Vector3(-0.035, -0.04, 0.03), skin)
	var arm_r := _add(pistol, Vector3(0.075, 0.075, 0.32), Vector3(0.05, -0.1, 0.2), sleeve)
	arm_r.rotation = Vector3(deg_to_rad(18), deg_to_rad(-8), 0)
	var arm_l := _add(pistol, Vector3(0.07, 0.07, 0.3), Vector3(-0.1, -0.1, 0.2), sleeve)
	arm_l.rotation = Vector3(deg_to_rad(18), deg_to_rad(25), 0)
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	_flash.mesh = q
	_flash.material_override = Mats.unshaded(Color(1.0, 0.8, 0.4, 0.95), true)
	_flash.position = Vector3(0, 0.025, -0.17)
	_flash.visible = false
	_flash.layers = L
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pistol.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.omni_range = 6.0
	_flash_light.light_energy = 0.0
	_flash_light.position = Vector3(0, 0.03, -0.25)
	pistol.add_child(_flash_light)


func _build_baton() -> void:
	var black := Mats.solid(Color("101114"), 0.5, 0.2)
	var skin := Mats.solid(Color("c69c7b"), 0.7)
	var sleeve := Mats.solid(Color("1f2d4d"), 0.85)
	var shaft := Node3D.new()
	shaft.rotation = Vector3(deg_to_rad(-60), 0, deg_to_rad(10))
	baton.add_child(shaft)
	var imported := _load_weapon_glb("baton", [])
	if imported:
		shaft.add_child(imported)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = Mats.cylinder(0.016, 0.55, 8)
		mi.material_override = black
		mi.position = Vector3(0, 0.27, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Combat.VIS_INTERIOR | Combat.VIS_EXTERIOR
		shaft.add_child(mi)
		_add(shaft, Vector3(0.05, 0.11, 0.05), Vector3(0, -0.02, 0), black)
	_add(shaft, Vector3(0.065, 0.075, 0.08), Vector3(0, -0.02, 0.01), skin)
	var arm := _add(baton, Vector3(0.075, 0.075, 0.32), Vector3(0.03, -0.08, 0.17), sleeve)
	arm.rotation = Vector3(deg_to_rad(20), 0, 0)


## Модель оружия из Blender-пайплайна (res://assets/models/weapons/<kind>.glb).
## Возвращает null, если файла нет или в нём нет обязательных узлов.
func _load_weapon_glb(kind: String, required: Array) -> Node3D:
	var path := "res://assets/models/weapons/%s.glb" % kind
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	for n in required:
		if inst.find_child(n, true, false) == null:
			push_warning("Viewmodel: в %s нет узла %s — использую встроенную модель" % [path, n])
			inst.free()
			return null
	return inst


func _add(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := Mats.add_mesh(parent, Mats.box(size), mat, pos, Vector3.ZERO, Combat.VIS_INTERIOR | Combat.VIS_EXTERIOR, false)
	return mi


## move_amount 0..1 — скорость игрока относительно максимума; look_delta — поворот камеры за кадр (рад).
func update_motion(delta: float, move_amount: float, look_delta: Vector2) -> void:
	_bob_t += delta * (2.0 + 7.0 * move_amount)
	_sway = _sway.lerp(Vector2(clampf(-look_delta.x * 2.5, -0.04, 0.04), clampf(look_delta.y * 2.5, -0.04, 0.04)), clampf(delta * 10.0, 0.0, 1.0))
	_kick = lerpf(_kick, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	if _switch_t > 0.0:
		_switch_t = maxf(0.0, _switch_t - delta)
	var bob := Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.01, 0.0) * (0.3 + move_amount)
	var switch_drop := Vector3(0, -0.25 * sin(_switch_t / 0.35 * PI), 0)
	var w: Node3D = pistol if _active == 0 else baton
	var rest := REST_PISTOL if _active == 0 else REST_BATON
	w.position = rest + bob + Vector3(_sway.x, _sway.y, _kick * 0.06) + switch_drop
	w.rotation = Vector3(_kick * 0.25, 0, 0)
	if _reload_t < 0.0:
		_slide.position.z = 0.035 * clampf(_kick * 1.5, 0.0, 1.0)
	# Перезарядка: увести вниз и повернуть, магазин выходит и возвращается.
	if _reload_t >= 0.0:
		_reload_t += delta
		var k := clampf(_reload_t / _reload_dur, 0.0, 1.0)
		var dip := sin(k * PI)
		pistol.position += Vector3(-0.03 * dip, -0.09 * dip, 0.03 * dip)
		pistol.rotation += Vector3(deg_to_rad(25) * dip, 0, deg_to_rad(35) * dip)
		var mag_k := clampf(1.0 - absf(k - 0.45) / 0.25, 0.0, 1.0)
		_mag.position = Vector3(0, -0.12 * mag_k, 0)
		_slide.position.z = 0.03 if k > 0.85 and k < 0.95 else 0.0
		if k >= 1.0:
			_reload_t = -1.0
			_mag.position = Vector3.ZERO
			_slide.position.z = 0.0
	# Удар дубинкой: замах вправо-вверх → резкий мах влево-вниз.
	if _swing_t >= 0.0:
		_swing_t += delta
		var s := clampf(_swing_t / SWING_DUR, 0.0, 1.0)
		var wind := clampf(s / 0.3, 0.0, 1.0)
		var strike := clampf((s - 0.3) / 0.25, 0.0, 1.0)
		var back := clampf((s - 0.55) / 0.45, 0.0, 1.0)
		var ang := lerpf(lerpf(0.0, 0.6, wind), -1.1, strike)
		ang = lerpf(ang, 0.0, back)
		baton.rotation = Vector3(ang * 0.6, ang * 0.9, ang * 0.5)
		baton.position += Vector3(-0.12 * strike * (1.0 - back), 0.04 * wind * (1.0 - strike), -0.1 * strike * (1.0 - back))
		if s >= 1.0:
			_swing_t = -1.0


func kick() -> void:
	_kick = 1.0
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash_light.light_energy = 2.5
	_flash_t = 0.045


func start_reload(duration: float) -> void:
	_reload_dur = maxf(duration, 0.1)
	_reload_t = 0.0


func cancel_reload() -> void:
	_reload_t = -1.0
	_mag.position = Vector3.ZERO


func swing() -> void:
	_swing_t = 0.0


func show_weapon(index: int) -> void:
	_active = index
	pistol.visible = index == 0
	baton.visible = index == 1
	_switch_t = 0.35
	cancel_reload()
	_swing_t = -1.0
	baton.rotation = Vector3.ZERO
