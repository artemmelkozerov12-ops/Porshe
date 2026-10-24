class_name Cutscene
extends Node3D
## Вступительный ролик миссии (≈13 с, можно пропустить):
##   1. Общий план улицы → грабители врываются в магазин.
##   2. Касса: угроза кассиру, кассир поднимает руки.
##   3. Рация диспетчера, патрульная машина с мигалками подъезжает.
##   4. Дверь открывается, полицейский выходит и идёт к магазину.
##   5. Камера плавно «влетает» в глаза игрока — управление передаётся игроку.
## Пропуск мгновенно приводит всех в итоговые позиции — состояние идентично полному просмотру.

signal finished

var m: Node                 # Mission
var cam: Camera3D
var cop: CharacterRig
var _done := false
var _tweens: Array[Tween] = []
var _siren: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _door := Vector3.ZERO
var _car_stop := Vector3.ZERO
var _cop_end := Vector3.ZERO
var _cam_tween: Tween


func setup(mission: Node) -> void:
	m = mission


func play() -> void:
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 150.0
	add_child(cam)
	cam.current = true
	m.hud.set_cinematic(true)
	m.hud.skip_requested.connect(skip, CONNECT_ONE_SHOT)
	_door = m.door_pos
	_car_stop = Vector3(_door.x + 3.2, 0, 6.2)
	_cop_end = Vector3(_door.x + 0.6, 0, 2.6)
	m.car.global_position = Vector3(_door.x - 42.0, 0, 6.2)
	m.car.rotation.y = -PI / 2.0
	for c in m.civilians:
		c.set_state(Civilian.S.CALM)

	# --- Кадр 1: улица, грабители бегут к двери.
	m.hud.set_caption(String(m.def["caption"]))
	_set_cam(Vector3(_door.x + 7.5, 2.1, 9.5), Vector3(_door.x - 1.0, 1.3, 0.0))
	_cam_move(Vector3(_door.x + 5.5, 1.8, 7.0), 3.2)
	var i := 0
	for b in m.bandits:
		_run_bandit_in(b, i)
		i += 1
	if not await _wait(2.7):
		return

	# --- Кадр 2: касса, угроза.
	var victim: Node3D = m.civilians[0] if m.civilians.size() > 0 else null
	var threat_b: Node3D = _threatening_bandit()
	if victim and threat_b:
		var mid: Vector3 = (victim.global_position + threat_b.home_pos) * 0.5
		var side: Vector3 = (victim.global_position - threat_b.home_pos).cross(Vector3.UP).normalized()
		# Камера — со стороны зала, а не стены.
		var r: Rect2 = m.builder.interior_rect()
		var inner := Vector3(r.get_center().x, 0, r.get_center().y) - mid
		if side.dot(inner) < 0.0:
			side = -side
		_set_cam(_inside(mid + side * 2.6) + Vector3(0, 1.55, 0), mid + Vector3(0, 1.3, 0))
		_cam_move(_inside(mid + side * 2.1) + Vector3(0, 1.5, 0), 3.6)
	m.hud.set_caption("")
	m.hud.set_subtitle("— Всем стоять! Деньги в пакет, живо!")
	if not await _wait(1.0):
		return
	for c in m.civilians:
		c.set_state(Civilian.S.HOSTAGE)
	if not await _wait(1.6):
		return
	m.hud.set_subtitle("— Не стреляйте… Берите всё!")
	if not await _wait(1.4):
		return

	# --- Кадр 3: рация, машина подъезжает.
	Sfx.play("radio", -2.0, 0.0)
	m.hud.set_subtitle("Диспетчер: «Всем экипажам, код 211 — вооружённое ограбление. %s»" % _address())
	m.car.set_lights(true)
	_siren = Sfx.loop_on(self, "siren", -10.0)
	_engine = Sfx.loop_on(self, "car_engine", -12.0)
	_set_cam(Vector3(_door.x + 14.0, 1.2, 9.0), Vector3(_door.x - 6.0, 0.8, 6.0))
	_tw().tween_property(m.car, "global_position", _car_stop, 3.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var spun := [0.0]
	_tw().tween_method(func(v: float):
		m.car.spin_wheels(v - spun[0])
		spun[0] = v, 0.0, -45.0, 3.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_cam_tween = _tw()
	_cam_tween.tween_property(cam, "rotation:y", cam.rotation.y + 0.35, 3.2).set_trans(Tween.TRANS_SINE)
	if not await _wait(3.3):
		return

	# --- Кадр 4: дверь, выход полицейского.
	m.hud.set_subtitle("")
	if _siren:
		var fade := _tw()
		fade.tween_property(_siren, "volume_db", -40.0, 1.5)
	if _engine:
		_engine.stop()
	Sfx.play_at("door", _car_stop, -2.0)
	if m.car.door_pivot:
		_tw().tween_property(m.car.door_pivot, "rotation:y", deg_to_rad(-70.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cop = CharacterRig.new()
	cop.name = "CopActor"
	add_child(cop)
	cop.setup("cop", Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
	var exit_pos: Vector3 = m.car.to_global(Vector3(-1.3, 0, 0.15))
	cop.global_position = exit_pos
	cop.rotation.y = Combat.yaw_from_dir(_cop_end - exit_pos)
	cop.play("idle", 0.0)
	_set_cam(exit_pos + Vector3(2.4, 1.75, 2.8), exit_pos + Vector3(-0.5, 1.2, -2.0))
	if not await _wait(0.6):
		return
	cop.play("walk", 0.2)
	_tw().tween_property(cop, "global_position", _cop_end, 2.2)
	_cam_move(_cop_end + Vector3(1.0, 1.85, 2.6), 2.4)
	if not await _wait(2.3):
		return

	# --- Кадр 5: камера влетает в глаза игрока.
	cop.play("idle", 0.2)
	_place_player()
	var target: Transform3D = m.player.camera.global_transform
	_kill_cam_tween()
	_cam_tween = _tw()
	_cam_tween.tween_property(cam, "global_transform", target, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if not await _wait(0.6):
		return
	cop.visible = false
	if not await _wait(0.35):
		return
	_finish()


func _address() -> String:
	var parts := String(m.def["caption"]).split("·")
	return parts[parts.size() - 1].strip_edges()


func skip() -> void:
	_finish()


func is_done() -> bool:
	return _done


## Ждать t секунд (масштаб времени учитывается). false — ролик уже завершён/пропущен.
func _wait(t: float) -> bool:
	var e := 0.0
	while e < t:
		if _done or not is_inside_tree():
			return false
		await get_tree().process_frame
		e += get_process_delta_time()
	return not _done


func _tw() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


## Новый кадр всегда гасит движение камеры из предыдущего (иначе твины «тянут» камеру сквозь стены).
func _set_cam(pos: Vector3, look: Vector3) -> void:
	_kill_cam_tween()
	cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)


func _cam_move(to: Vector3, dur: float) -> void:
	_kill_cam_tween()
	_cam_tween = _tw()
	_cam_tween.tween_property(cam, "global_position", to, dur).set_trans(Tween.TRANS_SINE)


func _kill_cam_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null


func _inside(p: Vector3) -> Vector3:
	var r: Rect2 = m.builder.interior_rect().grow(-0.6)
	return Vector3(clampf(p.x, r.position.x, r.end.x), p.y, clampf(p.z, r.position.y, r.end.y))


func _threatening_bandit() -> Node3D:
	for b in m.bandits:
		if b.role == "threaten":
			return b
	return m.bandits[0] if m.bandits.size() > 0 else null


## Маршрут грабителя: тротуар → дверь → по навмешу к своей позиции.
func _run_bandit_in(b: Node, i: int) -> void:
	var start := Vector3(_door.x - 5.0 - i * 1.3, 0, 1.8 + (i % 2) * 0.6)
	b.global_position = start
	b.rotation.y = Combat.yaw_from_dir(Vector3(1, 0, 0))
	b.rig.play("run", 0.0)
	var pts: Array[Vector3] = [Vector3(_door.x, 0, 1.2), Vector3(_door.x, 0, -0.9)]
	var map: RID = get_world_3d().navigation_map
	var nav := NavigationServer3D.map_get_path(map, pts[1], b.home_pos, true)
	if nav.size() >= 2:
		for k in range(1, nav.size()):
			pts.append(nav[k])
	else:
		pts.append(b.home_pos)
	var tw := _tw()
	tw.tween_interval(0.35 * i)
	var prev := start
	for p in pts:
		var d := prev.distance_to(p)
		if d < 0.05:
			continue
		var dir := p - prev
		tw.tween_callback(func(): b.rotation.y = Combat.yaw_from_dir(dir))
		tw.tween_property(b, "global_position", Vector3(p.x, 0, p.z), d / 5.5)
		prev = p
	tw.tween_callback(func():
		b.global_position = b.home_pos
		b.rotation.y = b.home_yaw
		b.rig.play("threaten" if b.role == "threaten" else "idle", 0.2))


func _place_player() -> void:
	var p: Node = m.player
	p.global_position = _cop_end
	var look_dir := Vector3(_door.x, 0, -2.0) - _cop_end
	p.set_look(Combat.yaw_from_dir(look_dir), -0.05)


## Итоговое состояние сцены — одинаковое при просмотре до конца и при пропуске.
func _finish() -> void:
	if _done:
		return
	_done = true
	for t in _tweens:
		if t and t.is_valid():
			t.kill()
	_tweens.clear()
	if _siren:
		_siren.stop()
	if _engine:
		_engine.stop()
	for b in m.bandits:
		b.global_position = b.home_pos
		b.rotation.y = b.home_yaw
	for c in m.civilians:
		c.set_state(Civilian.S.HOSTAGE)
	m.car.global_position = _car_stop
	m.car.rotation.y = -PI / 2.0
	m.car.set_lights(true)
	if m.car.door_pivot:
		m.car.door_pivot.rotation.y = deg_to_rad(-70.0)
	_place_player()
	if cop:
		cop.queue_free()
		cop = null
	if cam:
		cam.current = false
	m.player.camera.current = true
	m.hud.set_cinematic(false)
	finished.emit()
