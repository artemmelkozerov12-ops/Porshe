extends Node
## Скриншоты для визуальной проверки (нужен реальный рендерер, не headless):
##   SHOT_DIR=/путь xvfb-run godot --rendering-method gl_compatibility --resolution 1560x720 res://tests/screenshots.tscn

var main: Node
var out := ""


func _ready() -> void:
	out = OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(90)
	await _shot("01_menu")
	main.show_mission_select()
	await _frames(30)
	await _shot("02_select")
	for i in 3:
		var m: Mission = main.start_mission(i, false)
		await _until(func(): return m.phase == Mission.Phase.INTRO, 400)
		await _secs(1.6)
		await _shot("1%d_intro_a" % i)
		await _secs(3.0)
		await _shot("1%d_intro_b" % i)
		await _secs(4.6)
		await _shot("1%d_intro_c" % i)
		await _until(func(): return m.phase == Mission.Phase.PLAYING, 1500)
		await _secs(0.5)
		await _shot("2%d_play_street" % i)
		var door: Vector3 = m.door_pos
		m.player.global_position = Vector3(door.x, 0, -1.2)
		m.player.set_look(0.0, -0.08)
		await _secs(0.4)
		await _shot("3%d_play_inside" % i)
		m.player.max_hp = 1e6
		m.player.hp = 1e6
		m.noise(m.player.global_position, 60)
		await _secs(3.5)
		m.player.try_fire()
		await _frames(2)
		await _shot("4%d_combat" % i)
	var mm: Mission = main.current_screen()
	mm.pause()
	await _frames(10)
	await _shot("50_pause")
	mm.resume()
	for b in mm.bandits:
		b.apply_damage({"amount": 999.0, "kind": "bullet", "by_player": true})
	await _secs(2.5)
	await _shot("51_result")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	var e := 0.0
	while e < t:
		await get_tree().process_frame
		e += get_process_delta_time()


func _until(c: Callable, n: int) -> void:
	for i in n:
		if c.call():
			return
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(shot_name + ".png"))
	print("shot ", shot_name)
