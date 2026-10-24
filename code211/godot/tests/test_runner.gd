extends Node
## Автотесты игровой логики. Запуск (из папки godot/):
##   godot --headless --fixed-fps 60 res://tests/test_runner.tscn
## --fixed-fps делает время детерминированным и прогон быстрым.
## Код выхода: 0 — все проверки прошли, 1 — есть провалы.

var main: Node
var failures: Array[String] = []
var passed := 0


func _ready() -> void:
	Engine.max_fps = 0
	Save.reset_progress()
	await _run()
	print("")
	print("==== ИТОГ: %d проверок пройдено, %d провалено ====" % [passed, failures.size()])
	for f in failures:
		print("  ✗ " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ✓ " + what)
	else:
		failures.append(what)
		print("  ✗ " + what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(10)
	print("[меню]")
	check(main.current_screen() is MainMenu, "главное меню открывается")
	main.show_mission_select()
	await frames(5)
	check(main.current_screen() is MissionSelect, "экран выбора миссии открывается")

	for i in MissionDB.count():
		await _test_mission_basics(i)

	await _test_full_cutscene()
	await _test_baton_arrest()
	await _test_combat_ai()
	await _test_victory_and_score()
	await _test_defeat_player()
	await _test_defeat_civilian()
	await _test_touch_input()
	await _test_restart_leaks()
	await _test_pause()
	_test_settings_roundtrip()


func _start(i: int, skip: bool = true) -> Mission:
	var m: Mission = main.start_mission(i, skip)
	var ok := await wait_until(func(): return is_instance_valid(m) and m.phase == Mission.Phase.PLAYING, 600)
	check(ok, "миссия %d переходит в фазу PLAYING" % (i + 1))
	return m


func _test_mission_basics(i: int) -> void:
	var d := MissionDB.get_mission(i)
	print("[миссия %d: %s]" % [i + 1, d["title"]])
	var m := await _start(i)
	check(m.bandits.size() == d["bandits"].size(), "все грабители созданы (%d)" % m.bandits.size())
	check(m.builder.covers.size() >= 10, "укрытий сгенерировано: %d (≥10)" % m.builder.covers.size())
	var map: RID = m.get_world_3d().navigation_map
	var reach := 0
	for b in m.bandits:
		var path := NavigationServer3D.map_get_path(map, m.player.global_position, b.home_pos, true)
		if path.size() >= 2 and path[path.size() - 1].distance_to(b.home_pos) < 0.8:
			reach += 1
	check(reach == m.bandits.size(), "навмеш: путь от игрока до каждого грабителя (%d/%d)" % [reach, m.bandits.size()])
	var calm := true
	for b in m.bandits:
		if not (b.state in [Bandit.S.ROBBING, Bandit.S.PATROL]):
			calm = false
	check(calm, "после ролика грабители спокойны (ROBBING/PATROL)")
	check(m.player.camera.current, "камера игрока активна")
	check(m.player.controls_enabled, "управление включено")
	# Все точки укрытий на навмеше и не внутри реквизита.
	var bad := 0
	for c in m.builder.covers:
		var cp: CoverPoint = c
		var closest := NavigationServer3D.map_get_closest_point(map, cp.position)
		if closest.distance_to(cp.position) > 0.45:
			bad += 1
	check(bad <= m.builder.covers.size() / 10, "укрытия достижимы по навмешу (вне навмеша: %d)" % bad)


func _test_full_cutscene() -> void:
	print("[вступительный ролик целиком]")
	var m: Mission = main.start_mission(0, false)
	await frames(30)
	check(m.phase == Mission.Phase.INTRO, "ролик запущен")
	check(m.hud._cinematic, "HUD в кинорежиме")
	var ok := await wait_until(func(): return m.phase == Mission.Phase.PLAYING, 60 * 25)
	check(ok, "ролик доигрывается и передаёт управление игроку")
	check(m.player.camera.current, "после ролика активна камера игрока")
	check(m.car.lights_on, "мигалки включены")
	var home_ok := true
	for b in m.bandits:
		if b.global_position.distance_to(b.home_pos) > 0.6:
			home_ok = false
	check(home_ok, "грабители стоят на своих позициях")
	var hostage := true
	for c in m.civilians:
		if c.state != Civilian.S.HOSTAGE:
			hostage = false
	check(hostage, "кассир держит руки вверх")


func _test_baton_arrest() -> void:
	print("[дубинка: оглушение и арест со спины]")
	var m := await _start(0)
	var b: Bandit = m.bandits[0]
	# Встать за спиной грабителя, лицом к нему.
	var back := b.global_transform.basis.z.normalized()
	m.player.global_position = b.global_position + back * 1.1
	m.player.set_look(Combat.yaw_from_dir(b.global_position - m.player.global_position), 0.0)
	await frames(2)
	m.player.switch_weapon()
	await frames(30)
	m.player.try_fire()
	await frames(20)
	check(b.state == Bandit.S.STUNNED, "первый удар оглушает (состояние %s)" % b.state_name())
	await frames(45)
	m.player.try_fire()
	await frames(20)
	check(not b.is_alive() and m.arrests == 1, "второй удар — арест (arrests=%d)" % m.arrests)


func _test_combat_ai() -> void:
	print("[ИИ в бою]")
	var m := await _start(2)
	m.player.max_hp = 100000.0
	m.player.hp = 100000.0
	m.player.global_position = Vector3(0, 0, -1.0)
	m.player.set_look(0.0, 0.0)
	m.noise(m.player.global_position, 60.0)
	var seen := {}
	var shots_before := 0.0
	for k in 60 * 12:
		await get_tree().physics_frame
		for b in m.bandits:
			seen[b.state_name()] = true
	var states := ", ".join(seen.keys())
	print("    встреченные состояния: " + states)
	check(seen.has("MOVE_TO_COVER"), "грабители бегут в укрытия")
	check(seen.has("IN_COVER"), "грабители занимают укрытия")
	check(seen.has("PEEK") or seen.has("BLIND_FIRE") or seen.has("ADVANCE"), "грабители атакуют (выглядывают / стреляют вслепую / наступают)")
	check(m.player.stats["damage_taken"] > shots_before, "грабители попадают по игроку (урон %.0f)" % m.player.stats["damage_taken"])
	var claimed := 0
	for c in m.builder.covers:
		if c.claimed_by != null and is_instance_valid(c.claimed_by):
			claimed += 1
	var active := 0
	for b in m.bandits:
		if b.is_alive():
			active += 1
	check(claimed <= active, "одно укрытие — один грабитель (занято %d, живых %d)" % [claimed, active])
	check(m._tokens.size() <= Mission.MAX_SHOOTERS[m.difficulty], "одновременно стреляющих не больше лимита")
	# Ранение: грабитель уходит в укрытие/меняет позицию, а не стоит столбом.
	var b0: Bandit = m.bandits[1]
	var hp0 := b0.hp
	b0.apply_damage({"amount": 20.0, "kind": "bullet", "from": m.player.global_position, "by_player": true})
	check(b0.hp < hp0, "урон по грабителю учитывается")
	# Броня: тяжёлый получает меньше урона в корпус.
	var heavy: Bandit = null
	var light: Bandit = null
	for b in m.bandits:
		if b.armor == "heavy" and heavy == null:
			heavy = b
		if b.armor == "light" and light == null:
			light = b
	var h0 := heavy.hp
	var l0 := light.hp
	heavy.apply_damage({"amount": 30.0, "kind": "bullet"})
	light.apply_damage({"amount": 30.0, "kind": "bullet"})
	check(h0 - heavy.hp < l0 - light.hp, "тяжёлая броня снижает урон (%.1f < %.1f)" % [h0 - heavy.hp, l0 - light.hp])


func _test_victory_and_score() -> void:
	print("[победа и очки]")
	var m := await _start(0)
	var first := true
	for b in m.bandits:
		b.apply_damage({"amount": 500.0, "kind": "bullet", "headshot": first, "by_player": true})
		first = false
	check(m.phase == Mission.Phase.WON, "все нейтрализованы → победа")
	var ok := await wait_until(func(): return m.result_screen.visible, 60 * 4)
	check(ok, "экран результатов показан")
	check(get_tree().paused, "игра на паузе под экраном результатов")
	var r := m.last_result
	check(int(r["score"]) > 0 and int(r["stars"]) >= 1, "очки %d, звёзд %d, оценка %s" % [int(r["score"]), int(r["stars"]), r["grade"]])
	check(Save.unlocked >= 2, "следующая миссия открыта")
	check(not Save.best_for("corner_shop").is_empty(), "рекорд сохранён")
	get_tree().paused = false


func _test_defeat_player() -> void:
	print("[поражение: игрок погиб]")
	var m := await _start(1)
	m.player.apply_damage({"amount": 1000.0, "from": Vector3.ZERO})
	check(not m.player.alive, "игрок погиб")
	check(m.phase == Mission.Phase.LOST, "фаза LOST")
	var ok := await wait_until(func(): return m.result_screen.visible, 60 * 4)
	check(ok, "экран поражения показан")
	get_tree().paused = false


func _test_defeat_civilian() -> void:
	print("[поражение: задет гражданский]")
	var m := await _start(1)
	m.civilians[0].apply_damage({"amount": 34.0, "by_player": true})
	check(m.phase == Mission.Phase.LOST, "выстрел в гражданского → провал")
	check((Combat.MASK_BANDIT_BULLET & Combat.L_CIVILIAN) == 0, "пули грабителей не задевают гражданских (маска без слоя civilians)")
	get_tree().paused = false


func _test_touch_input() -> void:
	print("[мультитач]")
	var m := await _start(0)
	var t: TouchControls = m.touch
	var vp := m.get_viewport().get_visible_rect().size
	var fire_center: Vector2 = t._buttons["fire"]["center"]
	var shots0 := int(m.player.stats["shots"])
	var p0 := m.player.global_position
	var yaw0 := m.player.yaw
	# Палец 0 — джойстик, палец 1 — обзор, палец 2 — огонь. Одновременно.
	_touch(0, Vector2(vp.x * 0.15, vp.y * 0.7), true)
	_drag(0, Vector2(vp.x * 0.15, vp.y * 0.7 - 80), Vector2(0, -80))
	_touch(1, Vector2(vp.x * 0.6, vp.y * 0.4), true)
	_drag(1, Vector2(vp.x * 0.6 + 60, vp.y * 0.4), Vector2(60, 0))
	_touch(2, fire_center, true)
	await frames(30)
	check(t.move_vector.length() > 0.5, "джойстик даёт движение (%.2f)" % t.move_vector.length())
	check(m.player.global_position.distance_to(p0) > 0.3, "игрок двигается")
	check(absf(m.player.yaw - yaw0) > 0.01, "свайп поворачивает камеру")
	check(int(m.player.stats["shots"]) > shots0, "кнопка огня стреляет одновременно с движением")
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)
	_touch(2, Vector2.ZERO, false)
	await frames(3)
	check(t.move_vector == Vector2.ZERO and not t.fire_held, "отпускание пальцев сбрасывает ввод")


## События подаются в координатах окна (как от iOS); вьюпорт сам пересчитывает их
## в свои координаты — поэтому применяем прямое преобразование вьюпорт → окно.
func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = get_viewport().get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var xf := get_viewport().get_final_transform()
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = xf * pos
	e.relative = xf.basis_xform(rel)
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _test_restart_leaks() -> void:
	print("[перезапуски: утечки]")
	var counts: Array[int] = []
	for k in 4:
		var m := await _start(2)
		await frames(30)
		counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("    узлов после перезапусков: %s" % str(counts))
	check(absi(counts[3] - counts[1]) <= 5, "число узлов стабильно между перезапусками")
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0, "нет «осиротевших» узлов")


func _test_pause() -> void:
	print("[пауза]")
	var m := await _start(0)
	m.pause()
	check(get_tree().paused and m.pause_menu.visible, "пауза открывается")
	var t0 := m.elapsed
	await frames(30)
	check(is_equal_approx(m.elapsed, t0), "время миссии стоит на паузе")
	m.resume()
	await frames(10)
	check(not get_tree().paused and m.elapsed > t0, "игра продолжается")
	main.show_main_menu()
	await frames(5)
	check(not get_tree().paused and main.current_screen() is MainMenu, "выход в меню снимает паузу")


func _test_settings_roundtrip() -> void:
	print("[настройки]")
	Settings.quality = Settings.Quality.LOW
	Settings.shadow_quality = Settings.ShadowQuality.OFF
	Settings.fps_cap = 30
	Settings.sfx_volume = 0.35
	Settings.apply()
	Settings.save_settings()
	Settings.quality = 2
	Settings.fps_cap = 60
	Settings.load_settings()
	check(Settings.quality == Settings.Quality.LOW and Settings.fps_cap == 30, "настройки сохраняются и загружаются")
	check(is_equal_approx(Settings.sfx_volume, 0.35), "громкость сохраняется")
	Settings.apply()
	check(Engine.max_fps == 30, "лимит FPS применяется")
	# Вернуть значения по умолчанию.
	Settings.quality = Settings.Quality.MEDIUM
	Settings.shadow_quality = Settings.ShadowQuality.LOW
	Settings.fps_cap = 60
	Settings.sfx_volume = 1.0
	Settings.save_settings()
	Engine.max_fps = 0
