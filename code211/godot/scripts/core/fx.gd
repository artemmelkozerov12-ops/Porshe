class_name Fx
extends Node3D
## Боевые эффекты с пулами: трассеры, вспышки, искры/кровь, следы от пуль.
## Ничего не создаётся во время боя — только переиспользуется (стабильный кадр на iPhone).

const TRACERS := 16
const SPARKS := 10
const DECALS := 40
const FLASH_LIGHTS := 3

var _tracers: Array[MeshInstance3D] = []
var _tracer_life: PackedFloat32Array = PackedFloat32Array()
var _sparks: Array[CPUParticles3D] = []
var _blood: Array[CPUParticles3D] = []
var _decals: Array[Decal] = []
var _lights: Array[OmniLight3D] = []
var _light_life: PackedFloat32Array = PackedFloat32Array()
var _i_tracer := 0
var _i_spark := 0
var _i_blood := 0
var _i_decal := 0
var _i_light := 0
static var _hole_tex: ImageTexture


func _ready() -> void:
	for i in TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = Mats.box(Vector3(0.012, 0.012, 1.0))
		t.material_override = Mats.unique_unshaded(Color(1.0, 0.85, 0.45, 0.0))
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.layers = Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR
		t.visible = false
		add_child(t)
		_tracers.append(t)
	_tracer_life.resize(TRACERS)
	for i in SPARKS:
		_sparks.append(_make_particles(Color(1.0, 0.8, 0.4), 10, 5.0))
		_blood.append(_make_particles(Color(0.55, 0.05, 0.05), 12, 2.5))
	for i in DECALS:
		var d := Decal.new()
		d.size = Vector3(0.09, 0.2, 0.09)
		d.texture_albedo = _hole_texture()
		d.cull_mask = Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR
		d.visible = false
		add_child(d)
		_decals.append(d)
	for i in FLASH_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.4)
		l.omni_range = 5.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	_light_life.resize(FLASH_LIGHTS)


func _process(delta: float) -> void:
	for i in TRACERS:
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= delta
			var m := _tracers[i].material_override as StandardMaterial3D
			m.albedo_color.a = clampf(_tracer_life[i] / 0.07, 0.0, 1.0) * 0.9
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false
	for i in FLASH_LIGHTS:
		if _light_life[i] > 0.0:
			_light_life[i] -= delta
			_lights[i].light_energy = maxf(_light_life[i] / 0.06, 0.0) * 3.0
			if _light_life[i] <= 0.0:
				_lights[i].visible = false


func tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.3:
		return
	var t := _tracers[_i_tracer]
	_tracer_life[_i_tracer] = 0.07
	_i_tracer = (_i_tracer + 1) % TRACERS
	var mid := (from + to) * 0.5
	var dir := (to - from) / len
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	t.global_transform = Transform3D(Basis.looking_at(dir, up), mid)
	t.scale = Vector3(1.0, 1.0, len)
	t.visible = true


func flash(pos: Vector3) -> void:
	var l := _lights[_i_light]
	_light_life[_i_light] = 0.06
	_i_light = (_i_light + 1) % FLASH_LIGHTS
	l.global_position = pos
	l.light_energy = 3.0
	l.visible = true


func impact(pos: Vector3, normal: Vector3) -> void:
	var p := _sparks[_i_spark]
	_i_spark = (_i_spark + 1) % SPARKS
	_emit(p, pos, normal)
	_place_decal(pos, normal)


func blood(pos: Vector3, normal: Vector3) -> void:
	var p := _blood[_i_blood]
	_i_blood = (_i_blood + 1) % SPARKS
	_emit(p, pos, normal)


func _emit(p: CPUParticles3D, pos: Vector3, normal: Vector3) -> void:
	p.global_position = pos + normal * 0.02
	p.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	p.restart()
	p.emitting = true


func _place_decal(pos: Vector3, normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		return
	var d := _decals[_i_decal]
	_i_decal = (_i_decal + 1) % DECALS
	# Декаль проецирует вдоль своей -Y: выравниваем Y по нормали поверхности.
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.visible = true


func _make_particles(color: Color, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 40.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = Mats.box(Vector3(0.025, 0.025, 0.025))
	p.material_override = Mats.unshaded(color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR
	add_child(p)
	return p


## Текстура пулевого отверстия генерируется один раз (32×32, радиальный градиент).
static func _hole_texture() -> ImageTexture:
	if _hole_tex:
		return _hole_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := 0.0
			if d < 0.35:
				a = 0.95
			elif d < 1.0:
				a = (1.0 - d) / 0.65 * 0.55
			img.set_pixel(x, y, Color(0.05, 0.04, 0.035, a))
	_hole_tex = ImageTexture.create_from_image(img)
	return _hole_tex
