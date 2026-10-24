class_name Mission
extends Node3D
## Миссия целиком: уровень, участники, ролик, правила победы/поражения, очки,
## «жетоны огня» для ИИ, пауза, экран результатов.

signal request_menu
signal request_restart
signal request_next

enum Phase { LOADING, INTRO, PLAYING, WON, LOST }

const MAX_SHOOTERS := [1, 2, 3]       # одновременно стреляющих грабителей по сложности
const SCORE_KILL := 100
const SCORE_ARREST := 250
const SCORE_HEADSHOT := 50

var index := 0
var difficulty := 1
var skip_intro := false
var def: Dictionary
var builder: LevelBuilder
var fx: Fx
var player: Player
var car: PoliceCar
var bandits: Array = []
var civilians: Array = []
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var result_screen: ResultScreen
var cutscene: Cutscene
var door_pos := Vector3.ZERO
var visibility_factor := 1.0
var phase: Phase = Phase.LOADING
var elapsed := 0.0
var kills := 0
var arrests := 0
var headshot_kills := 0
var fail_reason := ""
var last_result: Dictionary = {}

var _tokens: Dictionary = {}
var _ui: CanvasLayer
var _top_ui: CanvasLayer
var _flicker_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_index: int, p_difficulty: int, p_skip_intro: bool = false) -> void:
	index = p_index
	difficulty = clampi(p_difficulty, 0, 2)
	skip_intro = p_skip_intro


func _ready() -> void:
	_rng.randomize()
	def = MissionDB.get_mission(index)
	builder = LevelBuilder.new()
	builder.build(self, def)
	door_pos = builder.door_positions()[0]
	match String(def["mood"]):
		"night":
			visibility_factor = 0.7
		"rain":
			visibility_factor = 0.85
		_:
			visibility_factor = 1.0
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	car = PoliceCar.new()
	car.name = "PoliceCar"
	add_child(car)
	car.global_position = Vector3(door_pos.x + 3.2, 0, 6.2)
	car.rotation.y = -PI / 2.0

	player = Player.new()
	player.name = "Player"
	player.mission = self
	add_child(player)
	player.global_position = Vector3(door_pos.x + 0.6, 0, 2.6)
	player.died.connect(_on_player_died)

	for bdef in def["bandits"]:
		var b := Bandit.new()
		b.setup(self, player, bdef, difficulty)
		add_child(b)
		b.global_position = bdef["pos"]
		b.rotation.y = b.home_yaw
		b.neutralized.connect(_on_bandit_neutralized)
		b.alerted.connect(_on_bandit_alerted)
		bandits.append(b)
	for cdef in def["civilians"]:
		var c := Civilian.new()
		c.setup(cdef)
		add_child(c)
		c.global_position = cdef["pos"]
		c.hurt.connect(_on_civilian_hurt)
		civilians.append(c)

	_build_ui()
	Settings.changed.connect(_on_settings_changed)
	Sfx.loop_on(self, "hum", -22.0)
	if def["mood"] == "rain":
		Sfx.loop_on(self, "rain", -14.0)

	# Навмеш запекается, когда вся статика уже зарегистрирована в физике.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	builder.bake_navigation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	builder.filter_covers(get_world_3d().navigation_map)
	_start_intro(skip_intro)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	hud = Hud.new()
	_ui.add_child(hud)
	hud.bind_player(player)
	touch = TouchControls.new()
	_ui.add_child(touch)
	touch.set_active(false)
	player.touch = touch
	touch.fire_pressed.connect(player.try_fire)
	touch.reload_pressed.connect(player.start_reload)
	touch.switch_pressed.connect(func():
		player.switch_weapon()
		touch.weapon = player.weapon)
	touch.crouch_pressed.connect(func():
		player.toggle_crouch()
		touch.crouched = player.crouched)
	touch.pause_pressed.connect(pause)

	_top_ui = CanvasLayer.new()
	_top_ui.layer = 20
	_top_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_top_ui)
	pause_menu = PauseMenu.new()
	_top_ui.add_child(pause_menu)
	pause_menu.visible = false
	pause_menu.resume_pressed.connect(resume)
	pause_menu.restart_pressed.connect(func(): request_restart.emit())
	pause_menu.menu_pressed.connect(func(): request_menu.emit())
	result_screen = ResultScreen.new()
	_top_ui.add_child(result_screen)
	result_screen.visible = false
	result_screen.retry_pressed.connect(func(): request_restart.emit())
	result_screen.next_pressed.connect(func(): request_next.emit())
	result_screen.menu_pressed.connect(func(): request_menu.emit())


# ======================================================================
# Фазы
# ======================================================================

func _start_intro(skip: bool) -> void:
	phase = Phase.INTRO
	if cutscene == null:
		cutscene = Cutscene.new()
		cutscene.setup(self)
		add_child(cutscene)
	cutscene.finished.connect(_start_gameplay, CONNECT_ONE_SHOT)
	cutscene.play()
	if skip:
		cutscene.skip()


func _start_gameplay() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.PLAYING
	elapsed = 0.0
	player.controls_enabled = true
	touch.set_active(true)
	for b in bandits:
		b.begin_ai()
	_update_objectives()
	hud.flash_message("НЕЙТРАЛИЗУЙТЕ ГРАБИТЕЛЕЙ", UiKit.AMBER, 2.2)


func _process(delta: float) -> void:
	if phase == Phase.PLAYING:
		elapsed += delta
		hud.set_timer(elapsed)
		if Input.is_action_just_pressed("pause"):
			pause()
	elif phase == Phase.INTRO and Input.is_action_just_pressed("skip") and cutscene:
		cutscene.skip()
	_flicker(delta)


func _flicker(delta: float) -> void:
	if builder == null or builder.flicker_lights.is_empty():
		return
	_flicker_t -= delta
	if _flicker_t > 0.0:
		return
	_flicker_t = _rng.randf_range(0.04, 0.5)
	var base: float = def.get("light_energy", 1.0)
	for l in builder.flicker_lights:
		l.light_energy = base * (0.08 if _rng.randf() < 0.35 else _rng.randf_range(0.8, 1.1))


func _notification(what: int) -> void:
	# iOS: свернули приложение / пришёл звонок — пауза, чтобы не умереть «в фоне».
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if phase == Phase.PLAYING and is_inside_tree() and not get_tree().paused:
			pause()


func pause() -> void:
	if phase != Phase.PLAYING:
		return
	get_tree().paused = true
	touch.reset()
	pause_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	pause_menu.visible = false
	get_tree().paused = false


# ======================================================================
# Сервисы для ИИ
# ======================================================================

## Шум выстрела: грабители в радиусе поднимают тревогу.
func noise(pos: Vector3, radius: float) -> void:
	if phase != Phase.PLAYING or radius <= 0.0:
		return
	for b in bandits:
		if b.is_alive() and b.global_position.distance_to(pos) <= radius:
			b.hear_noise(pos)


func request_token(b: Node) -> bool:
	if _tokens.has(b):
		return true
	for k in _tokens.keys():
		if not is_instance_valid(k) or not k.is_alive():
			_tokens.erase(k)
	if _tokens.size() < MAX_SHOOTERS[difficulty]:
		_tokens[b] = true
		return true
	return false


func release_token(b: Node) -> void:
	_tokens.erase(b)


## Лучшее укрытие для грабителя от угрозы `threat`.
func find_cover(b: Node, threat: Vector3) -> CoverPoint:
	var space := get_world_3d().direct_space_state
	var best: CoverPoint = null
	var best_s := -INF
	var bpos: Vector3 = b.global_position
	var b_to_threat := bpos.distance_to(threat)
	for c in builder.covers:
		var cp: CoverPoint = c
		if not cp.is_free_for(b) or _near_claimed(cp, b):
			continue
		var d_self := bpos.distance_to(cp.position)
		if d_self > 14.0:
			continue
		var d_threat := Vector2(cp.position.x - threat.x, cp.position.z - threat.z).length()
		if d_threat < 3.0:
			continue
		if not cp.protects(space, threat):
			continue
		var s := -d_self - absf(d_threat - 8.0) * 0.6
		if cp.peek_sees(space, threat):
			s += 4.0
		if d_threat < b_to_threat - 2.0:
			s -= 2.5   # не бежать навстречу стволу
		s += _rng.randf_range(0.0, 0.8)
		if s > best_s:
			best_s = s
			best = cp
	return best


func _near_claimed(cp: CoverPoint, who: Node) -> bool:
	for c in builder.covers:
		var o: CoverPoint = c
		if o == cp or o.claimed_by == null or o.claimed_by == who or not is_instance_valid(o.claimed_by):
			continue
		if o.position.distance_to(cp.position) < 1.1:
			return true
	return false


func spawn_blood(pos: Vector3, normal: Vector3) -> void:
	fx.blood(pos, normal)


# ======================================================================
# События
# ======================================================================

func _on_bandit_alerted(_b: Node) -> void:
	for c in civilians:
		if c.state == Civilian.S.HOSTAGE:
			c.set_state(Civilian.S.COWER)


func _on_bandit_neutralized(b: Node, arrested: bool, headshot: bool) -> void:
	release_token(b)
	if arrested:
		arrests += 1
		hud.feed("АРЕСТ  +%d" % SCORE_ARREST, UiKit.GREEN)
	else:
		kills += 1
		if headshot:
			headshot_kills += 1
		hud.feed("НЕЙТРАЛИЗОВАН  +%d" % (SCORE_KILL + (SCORE_HEADSHOT if headshot else 0)), UiKit.TEXT)
	# Остальные слышат и поднимают тревогу.
	noise(b.global_position, 25.0)
	_update_objectives()
	if remaining() == 0:
		_win()


func _on_civilian_hurt(_c: Node) -> void:
	_lose("Пострадал гражданский. Операция провалена.")


func _on_player_died() -> void:
	_lose("Офицер ранен. Нужна подмога.")


func _on_settings_changed() -> void:
	if builder:
		builder.apply_graphics()


func remaining() -> int:
	var n := 0
	for b in bandits:
		if b.is_alive():
			n += 1
	return n


func _update_objectives() -> void:
	var total := bandits.size()
	var lines := "Грабители: %d / %d нейтрализовано" % [total - remaining(), total]
	if civilians.size() > 0:
		lines += "\nГражданские: %d — не задеть" % civilians.size()
	hud.set_objectives(lines)


# ======================================================================
# Итоги
# ======================================================================

func _win() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.WON
	player.controls_enabled = false
	touch.set_active(false)
	for c in civilians:
		c.set_state(Civilian.S.SAFE)
	hud.flash_message("ЧИСТО. УГРОЗА УСТРАНЕНА", UiKit.GREEN, 2.0)
	Sfx.play("victory", -4.0, 0.0)
	last_result = compute_result(true)
	var is_record := Save.record(index, String(def["id"]), int(last_result["score"]), int(last_result["stars"]), String(last_result["grade"]))
	last_result["record"] = is_record
	_show_result_later(1.6)


func _lose(reason: String) -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.LOST
	fail_reason = reason
	player.controls_enabled = false
	touch.set_active(false)
	Sfx.play("defeat", -4.0, 0.0)
	last_result = compute_result(false)
	_show_result_later(1.8)


func _show_result_later(t: float) -> void:
	await get_tree().create_timer(t, false).timeout
	if not is_inside_tree():
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	result_screen.open(last_result, def, index < MissionDB.count() - 1 and phase == Phase.WON)


func compute_result(won: bool) -> Dictionary:
	var st: Dictionary = player.stats
	var shots := int(st["shots"])
	var hits := int(st["hits"])
	var acc := float(hits) / float(shots) if shots > 0 else 1.0
	var civ_ok := true
	for c in civilians:
		if c.collision_layer == 0:
			civ_ok = false
	var breakdown := {
		"neutralized": kills * SCORE_KILL,
		"arrests": arrests * SCORE_ARREST,
		"headshots": headshot_kills * SCORE_HEADSHOT,
		"accuracy": int(acc * 400.0),
		"time": maxi(0, int(600.0 - elapsed * 4.0)),
		"health": int(clampf(player.hp, 0.0, 100.0) * 4.0),
		"civilians": 300 if civ_ok else 0,
	}
	var raw := 0
	for k in breakdown:
		raw += int(breakdown[k])
	var mult: float = [0.8, 1.0, 1.35][difficulty]
	var score := int(raw * mult) if won else 0
	var par := 900 + bandits.size() * 150
	var stars := 0
	if won:
		stars = 1
		if score >= int(par * 0.75):
			stars = 2
		if score >= par:
			stars = 3
	var grade := "—"
	if won:
		grade = "C"
		if stars == 2:
			grade = "B"
		if stars == 3:
			grade = "A"
		if stars == 3 and acc >= 0.6 and player.hp >= 70.0:
			grade = "S"
	return {
		"won": won, "score": score, "stars": stars, "grade": grade, "time": elapsed,
		"accuracy": acc, "shots": shots, "hits": hits, "headshots": int(st["headshots"]),
		"kills": kills, "arrests": arrests, "damage_taken": float(st["damage_taken"]),
		"health": player.hp, "breakdown": breakdown, "multiplier": mult, "reason": fail_reason,
		"record": false,
	}
