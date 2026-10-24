class_name Player
extends CharacterBody3D
## Полицейский (вид от первого лица).
## Ввод: TouchControls (iPhone) + клавиатура/мышь (отладка на Mac/ПК).
## Оружие: пистолет (магазин 17, отдача, разброс, перезарядка) и дубинка
## (удар оглушает, повторный — арест).

signal health_changed(hp: float, max_hp: float)
signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(index: int)
signal died
signal damaged(from_pos: Vector3)
signal hit_confirmed(kill: bool, headshot: bool, arrest: bool)
signal reload_progress(p: float)
signal crouch_changed(crouched: bool)

const WALK_SPEED := 3.6
const CROUCH_SPEED := 1.8
const EYE_STAND := 1.62
const EYE_CROUCH := 1.0
const H_STAND := 1.8
const H_CROUCH := 1.2
const GRAVITY := 9.8
const LOOK_DEG_PER_PX := 0.16
const PITCH_LIMIT := 1.45

const PISTOL_MAG := 17
const PISTOL_RESERVE := 85
const PISTOL_DMG := 34.0
const PISTOL_RATE := 0.16
const BATON_RANGE := 1.9
const BATON_DMG := 40.0
const BATON_RATE := 0.65
const ASSIST_DEG := 2.6

var max_hp := 100.0
var hp := 100.0
var alive := true
var crouched := false
var controls_enabled := false
var mission: Node
var touch: TouchControls
var head: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var yaw := 0.0
var pitch := 0.0
var weapon := 0              # 0 — пистолет, 1 — дубинка
var mag := PISTOL_MAG
var reserve := PISTOL_RESERVE
var stats := {"shots": 0, "hits": 0, "headshots": 0, "damage_taken": 0.0, "melee": 0}

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _recoil := 0.0
var _spread := 0.0
var _fire_cd := 0.0
var _reloading := false
var _reload_t := 0.0
var _reload_dur := 1.5
var _reload_in_played := false
var _switch_t := 0.0
var _baton_pending := -1.0
var _shake := 0.0
var _step_dist := 0.0
var _eye := EYE_STAND
var _last_look := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	collision_layer = Combat.L_PLAYER
	collision_mask = Combat.L_WORLD | Combat.L_GLASS | Combat.L_BANDIT | Combat.L_CIVILIAN
	floor_snap_length = 0.3
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.33
	_capsule.height = H_STAND
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = H_STAND / 2.0
	add_child(_shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = EYE_STAND
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 72.0
	camera.near = 0.03
	camera.far = 120.0
	head.add_child(camera)
	viewmodel = Viewmodel.new()
	viewmodel.name = "Viewmodel"
	camera.add_child(viewmodel)
	yaw = rotation.y


func set_look(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch
	rotation.y = yaw
	head.rotation.x = pitch


# ---------------------------------------------------------------- точки для ИИ

func head_position() -> Vector3:
	return global_position + Vector3(0, _eye, 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, _eye - 0.45, 0)


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * 0.7)
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			try_fire()
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("switch_weapon"):
		switch_weapon()
	elif event.is_action_pressed("crouch"):
		toggle_crouch()


func _look(px: Vector2) -> void:
	var sens := Settings.look_sensitivity * deg_to_rad(LOOK_DEG_PER_PX)
	# «Трение» прицела: рядом с целью поворот медленнее — помогает на тач-экране.
	if Settings.aim_assist and _target_near_crosshair(4.0):
		sens *= 0.55
	var dy := px.y * (-1.0 if Settings.invert_y else 1.0)
	yaw -= px.x * sens
	pitch = clampf(pitch - dy * sens, -PITCH_LIMIT, PITCH_LIMIT)
	_last_look += Vector2(px.x * sens, dy * sens)


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	if controls_enabled and alive and touch:
		var d := touch.consume_look_delta()
		if d != Vector2.ZERO:
			_look(d)
	_fire_cd -= delta
	_spread = maxf(0.0, _spread - delta * 6.0)
	_recoil = lerpf(_recoil, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if alive:
		rotation.y = yaw
		head.rotation.x = clampf(pitch + _recoil, -PITCH_LIMIT, PITCH_LIMIT)
	_eye = lerpf(_eye, EYE_CROUCH if crouched else EYE_STAND, clampf(delta * 10.0, 0.0, 1.0))
	if alive:
		head.position.y = _eye
	# Тряска камеры (попадания, близкие пули).
	_shake = maxf(0.0, _shake - delta * 2.5)
	camera.h_offset = _rng.randf_range(-1.0, 1.0) * _shake * 0.03
	camera.v_offset = _rng.randf_range(-1.0, 1.0) * _shake * 0.03
	if _switch_t > 0.0:
		_switch_t -= delta
	if _reloading:
		_reload_t += delta
		reload_progress.emit(clampf(_reload_t / _reload_dur, 0.0, 1.0))
		if not _reload_in_played and _reload_t > _reload_dur * 0.65:
			_reload_in_played = true
			Sfx.play("reload_in", -3.0)
		if _reload_t >= _reload_dur:
			_finish_reload()
	if _baton_pending >= 0.0:
		_baton_pending -= delta
		if _baton_pending < 0.0:
			_baton_hit_check()
	var hv := Vector2(velocity.x, velocity.z).length()
	viewmodel.update_motion(delta, clampf(hv / WALK_SPEED, 0.0, 1.0), _last_look)
	_last_look = Vector2.ZERO
	# Удержание кнопки огня: повтор раз в ~0.3 с (пистолет остаётся полуавтоматическим по темпу).
	if controls_enabled and alive and touch and touch.fire_held and _fire_cd <= -0.14:
		try_fire()


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled and alive:
		if touch:
			input = touch.move_vector
		var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if kb.length() > input.length():
			input = kb
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var speed := CROUCH_SPEED if crouched else WALK_SPEED
	var target := dir * speed
	var accel := 28.0 if input != Vector2.ZERO else 22.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z).length()
	_step_dist += hv * delta
	if _step_dist > (0.55 if crouched else 0.75):
		_step_dist = 0.0
		Sfx.play("step", -14.0 if crouched else -8.0, 0.15)


# ---------------------------------------------------------------- оружие

func try_fire() -> void:
	if not controls_enabled or not alive or _switch_t > 0.0:
		return
	if weapon == 1:
		_baton_attack()
		return
	if _reloading or _fire_cd > 0.0:
		return
	if mag <= 0:
		Sfx.play("dry")
		_fire_cd = 0.25
		start_reload()
		return
	mag -= 1
	_fire_cd = PISTOL_RATE
	stats["shots"] += 1
	var cam_xf := camera.global_transform
	var dir := -cam_xf.basis.z
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	dir = Combat.spread_dir(dir, _spread + (0.8 if moving else 0.0), _rng)
	if Settings.aim_assist:
		dir = _assist(cam_xf.origin, dir)
	var from := cam_xf.origin
	var space := get_world_3d().direct_space_state
	var hit := Combat.ray(space, from, from + dir * 90.0, Combat.MASK_PLAYER_BULLET, [get_rid()])
	var end := from + dir * 90.0
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		if col is Bandit:
			var b := col as Bandit
			var headshot := b.is_head_hit(hit["position"])
			var was_alive := b.is_alive()
			b.apply_damage({"amount": PISTOL_DMG, "headshot": headshot, "kind": "bullet", "from": global_position,
				"hit_pos": hit["position"], "normal": hit["normal"], "by_player": true})
			stats["hits"] += 1
			if headshot:
				stats["headshots"] += 1
			hit_confirmed.emit(was_alive and not b.is_alive(), headshot, false)
		elif col is Civilian:
			(col as Civilian).apply_damage({"amount": PISTOL_DMG, "kind": "bullet", "by_player": true})
		else:
			if mission:
				mission.fx.impact(hit["position"], hit["normal"])
			Sfx.play_at("impact", hit["position"], -6.0)
	if mission:
		var muzzle := from + dir * 0.6 + cam_xf.basis.x * 0.15 - cam_xf.basis.y * 0.12
		mission.fx.tracer(muzzle, end)
		mission.noise(global_position, 30.0)
	_recoil += deg_to_rad(2.4)
	_spread = minf(_spread + 1.0, 5.0)
	viewmodel.kick()
	Sfx.play("shot", 0.0, 0.04)
	ammo_changed.emit(mag, reserve)
	if mag == 0 and reserve > 0:
		start_reload()


## Доводка прицела: если цель в пределах ASSIST_DEG от луча и видна — пуля летит в неё.
func _assist(from: Vector3, dir: Vector3) -> Vector3:
	if mission == null:
		return dir
	var best_dir := dir
	var best_ang := deg_to_rad(ASSIST_DEG)
	var space := get_world_3d().direct_space_state
	for b in mission.bandits:
		if not is_instance_valid(b) or not b.is_alive():
			continue
		for p in [b.head_position(), b.chest_position()]:
			var to: Vector3 = p - from
			var dist := to.length()
			if dist > 40.0 or dist < 0.5:
				continue
			var ang := dir.angle_to(to / dist)
			if ang < best_ang and Combat.line_clear(space, from, p):
				best_ang = ang
				best_dir = to / dist
	return best_dir


func _target_near_crosshair(deg: float) -> bool:
	if mission == null:
		return false
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var lim := deg_to_rad(deg)
	for b in mission.bandits:
		if is_instance_valid(b) and b.is_alive():
			var to: Vector3 = b.chest_position() - from
			if to.length() < 40.0 and dir.angle_to(to.normalized()) < lim:
				return true
	return false


func _baton_attack() -> void:
	if _fire_cd > 0.0:
		return
	_fire_cd = BATON_RATE
	viewmodel.swing()
	Sfx.play("baton_swing", -2.0)
	_baton_pending = 0.14   # попадание в момент удара анимации


func _baton_hit_check() -> void:
	if not alive or mission == null:
		return
	var fwd := -global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var best: Bandit = null
	var best_d := BATON_RANGE + 0.01
	for b in mission.bandits:
		if not is_instance_valid(b) or not b.is_alive():
			continue
		var to: Vector3 = b.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > BATON_RANGE or d < 0.01:
			continue
		if fwd.dot(to / d) < 0.55:
			continue
		if not Combat.line_clear(space, head_position(), b.chest_position()):
			continue
		if d < best_d:
			best_d = d
			best = b
	if best:
		best.apply_damage({"amount": BATON_DMG, "kind": "melee", "from": global_position, "by_player": true})
		stats["melee"] += 1
		_shake = maxf(_shake, 0.4)
		hit_confirmed.emit(false, false, not best.is_alive())


func start_reload() -> void:
	if _reloading or weapon != 0 or mag >= PISTOL_MAG or reserve <= 0 or not alive:
		return
	_reloading = true
	_reload_t = 0.0
	_reload_in_played = false
	_reload_dur = 1.45 if mag > 0 else 1.9
	viewmodel.start_reload(_reload_dur)
	Sfx.play("reload_out", -3.0)


func _finish_reload() -> void:
	_reloading = false
	var take := mini(PISTOL_MAG - mag, reserve)
	mag += take
	reserve -= take
	reload_progress.emit(-1.0)
	ammo_changed.emit(mag, reserve)


func cancel_reload() -> void:
	if _reloading:
		_reloading = false
		viewmodel.cancel_reload()
		reload_progress.emit(-1.0)


func get_spread() -> float:
	return _spread


func is_reloading() -> bool:
	return _reloading


func switch_weapon() -> void:
	if not alive or not controls_enabled:
		return
	cancel_reload()
	weapon = 1 - weapon
	_switch_t = 0.35
	_baton_pending = -1.0
	viewmodel.show_weapon(weapon)
	Sfx.play("reload_out", -10.0)
	weapon_changed.emit(weapon)


func toggle_crouch() -> void:
	if not alive:
		return
	if crouched:
		# Встать можно, только если над головой свободно.
		var space := get_world_3d().direct_space_state
		if not Combat.line_clear(space, global_position + Vector3(0, H_CROUCH, 0), global_position + Vector3(0, H_STAND + 0.05, 0)):
			return
	crouched = not crouched
	_capsule.height = H_CROUCH if crouched else H_STAND
	_shape.position.y = _capsule.height / 2.0
	crouch_changed.emit(crouched)


# ---------------------------------------------------------------- урон

func apply_damage(info: Dictionary) -> void:
	if not alive:
		return
	var amount := float(info.get("amount", 0.0))
	hp = maxf(0.0, hp - amount)
	stats["damage_taken"] += amount
	_shake = minf(1.0, _shake + 0.6)
	var from: Vector3 = info.get("from", global_position)
	damaged.emit(from)
	health_changed.emit(hp, max_hp)
	Sfx.play("hurt", -2.0)
	if hp <= 0.0:
		_die()


func near_miss(_from: Vector3) -> void:
	_shake = minf(1.0, _shake + 0.15)


func _die() -> void:
	alive = false
	controls_enabled = false
	cancel_reload()
	viewmodel.visible = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "position:y", 0.3, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(head, "rotation:z", 1.2, 0.8).set_ease(Tween.EASE_IN)
	died.emit()
