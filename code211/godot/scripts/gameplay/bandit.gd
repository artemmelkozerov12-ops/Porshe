class_name Bandit
extends CharacterBody3D
## Грабитель. Конечный автомат тактического ИИ:
##
##   SCRIPTED ─(ролик закончился)→ ROBBING / PATROL
##   ROBBING/PATROL ─(увидел игрока / услышал выстрел / ранен)→ бой
##   Бой: MOVE_TO_COVER → IN_COVER ⇄ PEEK | BLIND_FIRE | RELOAD
##        нет укрытия → ADVANCE (стреляет стоя, ищет укрытие заново)
##   Дубинка: первый удар → STUNNED, второй (или по оглушённому) → DOWN (арест)
##   HP ≤ 0 → DOWN (смерть)
##
## Стреляют одновременно не все: право на огонь выдаёт миссия («жетоны»),
## их число зависит от сложности — так бой читаемый и честный на телефоне.

signal neutralized(bandit: Bandit, arrested: bool, headshot: bool)
signal alerted(bandit: Bandit)

enum S { SCRIPTED, ROBBING, PATROL, MOVE_TO_COVER, IN_COVER, PEEK, BLIND_FIRE, RELOAD, ADVANCE, STUNNED, DOWN }

const STATE_NAMES := ["SCRIPTED", "ROBBING", "PATROL", "MOVE_TO_COVER", "IN_COVER", "PEEK", "BLIND_FIRE",
	"RELOAD", "ADVANCE", "STUNNED", "DOWN"]

const ARMOR := {
	"light": {"hp": 70.0, "torso": 0.0, "head": 0.0, "mag": 8, "rig": "bandit_light", "speed": 3.6, "dmg": 1.0},
	"medium": {"hp": 90.0, "torso": 0.35, "head": 0.0, "mag": 8, "rig": "bandit_medium", "speed": 3.3, "dmg": 1.0},
	"heavy": {"hp": 130.0, "torso": 0.55, "head": 0.45, "mag": 12, "rig": "bandit_heavy", "speed": 2.8, "dmg": 1.25},
}
## Параметры по сложности: множитель HP, урон за попадание, разброс (°), реакция (с),
## время прицеливания (с), минимум времени в укрытии (с).
const DIFF := [
	{"hp": 0.8, "dmg": 7.0, "spread": 5.5, "react": 0.9, "aim": 0.8, "cover_min": 1.7},
	{"hp": 1.0, "dmg": 11.0, "spread": 3.6, "react": 0.6, "aim": 0.55, "cover_min": 1.2},
	{"hp": 1.25, "dmg": 15.0, "spread": 2.4, "react": 0.35, "aim": 0.35, "cover_min": 0.8},
]
const STAND_H := 1.75
const CROUCH_H := 1.15
const EYE_STAND := 1.6
const EYE_CROUCH := 1.0
const VIEW_DIST := 22.0
const VIEW_FOV_COS := 0.4
const HEAD_ZONE := 0.3
const GRAVITY := 9.8

var armor := "light"
var role := "patrol"
var max_hp := 70.0
var hp := 70.0
var state: S = S.SCRIPTED
var mission: Node          # Mission (нетипизировано: избегаем циклических зависимостей классов)
var player: Node           # Player
var rig: CharacterRig
var agent: NavigationAgent3D
var cover: CoverPoint
var patrol_points: Array[Vector3] = []
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var awareness := 0.0
var ammo := 8
var mag_size := 8
var stunned_by_stealth := false

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _d: Dictionary
var _speed := 3.5
var _dmg_mult := 1.0
var _t := 0.0
var _think := 0.0
var _state_timer := 0.0
var _shots_left := 0
var _shot_cd := 0.0
var _aim_t := 0.0
var _flinch := 0.0
var _crouched := false
var _has_token := false
var _patrol_i := 0
var _patrol_wait := 0.0
var _alert_delay := -1.0
var _pending_alert_pos := Vector3.ZERO
var _perceive_t := 0.0
var _peek_saw := false
var _blind_misses := 0
var _rng := RandomNumberGenerator.new()
var _alert_mark: Label3D
var _stuck_t := 0.0
var _mark_t := 0.0


func setup(p_mission: Node, p_player: Node, bdef: Dictionary, difficulty: int) -> void:
	mission = p_mission
	player = p_player
	armor = String(bdef.get("armor", "light"))
	if not ARMOR.has(armor):
		armor = "light"
	role = String(bdef.get("role", "patrol"))
	var a: Dictionary = ARMOR[armor]
	_d = DIFF[clampi(difficulty, 0, 2)]
	max_hp = float(a["hp"]) * float(_d["hp"])
	hp = max_hp
	mag_size = int(a["mag"])
	ammo = mag_size
	_speed = float(a["speed"])
	_dmg_mult = float(a["dmg"])
	home_pos = bdef["pos"]
	home_yaw = deg_to_rad(float(bdef.get("face", 0.0)))
	for p in bdef.get("patrol", []):
		patrol_points.append(p)
	_rng.randomize()


func _ready() -> void:
	collision_layer = Combat.L_BANDIT
	collision_mask = Combat.L_WORLD | Combat.L_GLASS | Combat.L_PLAYER
	floor_snap_length = 0.3
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = STAND_H
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_H / 2.0
	add_child(_shape)
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(ARMOR[armor]["rig"])
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.45
	agent.target_desired_distance = 0.35
	agent.radius = 0.3
	agent.height = STAND_H
	agent.avoidance_enabled = false
	add_child(agent)
	_alert_mark = Label3D.new()
	_alert_mark.text = "!"
	_alert_mark.font_size = 96
	_alert_mark.pixel_size = 0.006
	_alert_mark.modulate = Color(1.0, 0.25, 0.2)
	_alert_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_mark.no_depth_test = true
	_alert_mark.shaded = false
	_alert_mark.position = Vector3(0, 2.15, 0)
	_alert_mark.visible = false
	_alert_mark.layers = Combat.VIS_INTERIOR | Combat.VIS_EXTERIOR
	add_child(_alert_mark)
	rig.play("idle", 0.0)


# ======================================================================
# Публичный интерфейс
# ======================================================================

func is_alive() -> bool:
	return state != S.DOWN


func is_in_combat() -> bool:
	return state in [S.MOVE_TO_COVER, S.IN_COVER, S.PEEK, S.BLIND_FIRE, S.RELOAD, S.ADVANCE]


func state_name() -> String:
	return STATE_NAMES[state]


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_CROUCH if _crouched else EYE_STAND, 0)


func chest_position() -> Vector3:
	return global_position + Vector3(0, 0.75 if _crouched else 1.3, 0)


func head_position() -> Vector3:
	return global_position + Vector3(0, _capsule.height - 0.15, 0)


func is_head_hit(p: Vector3) -> bool:
	return p.y - global_position.y > _capsule.height - HEAD_ZONE


## Вызывается миссией после ролика.
func begin_ai() -> void:
	if state != S.SCRIPTED:
		return
	global_position = home_pos
	rotation.y = home_yaw
	_set_state(S.PATROL if (role == "patrol" or role == "guard") and patrol_points.size() >= 2 else S.ROBBING)


## Шум (выстрел): тревога с небольшой задержкой — реакция не мгновенная.
func hear_noise(pos: Vector3) -> void:
	if state in [S.ROBBING, S.PATROL] and _alert_delay < 0.0:
		_alert_delay = float(_d["react"]) * _rng.randf_range(0.6, 1.3)
		_pending_alert_pos = pos


func become_alert(_pos: Vector3) -> void:
	if state in [S.DOWN, S.STUNNED, S.SCRIPTED] or is_in_combat():
		return
	awareness = 1.0
	_alert_delay = -1.0
	_show_alert_mark()
	alerted.emit(self)
	Sfx.play_at("alert", eye_position(), -6.0)
	_choose_cover_or_advance()


func apply_damage(info: Dictionary) -> void:
	if state == S.DOWN:
		return
	var kind := String(info.get("kind", "bullet"))
	if kind == "melee":
		_on_melee(info)
		return
	var head := bool(info.get("headshot", false))
	var amount := float(info.get("amount", 0.0))
	var a: Dictionary = ARMOR[armor]
	var reduce: float = float(a["head"]) if head else float(a["torso"])
	var dmg := amount * (1.0 - reduce) * (2.5 if head else 1.0)
	hp -= dmg
	if mission and mission.has_method("spawn_blood"):
		mission.spawn_blood(info.get("hit_pos", chest_position()), info.get("normal", Vector3.UP))
	if hp <= 0.0:
		_go_down(false, head)
		return
	_flinch = 0.32
	rig.play("c_hit" if _crouched else "hit", 0.05, 1.0, true)
	Sfx.play_at("hit_flesh", chest_position(), -2.0)
	if state == S.STUNNED:
		return
	if not is_in_combat():
		become_alert(info.get("from", global_position))
		return
	# Ранен на открытом месте → назад в укрытие.
	if state in [S.PEEK, S.ADVANCE] and (hp < max_hp * 0.5 or _rng.randf() < 0.4):
		_release_token()
		if cover and _cover_still_good():
			_set_state(S.IN_COVER)
		else:
			_choose_cover_or_advance()
	elif state == S.PEEK:
		_aim_t = maxf(0.0, _aim_t - 0.25)


func _on_melee(info: Dictionary) -> void:
	Sfx.play_at("baton_hit", chest_position())
	if state == S.STUNNED:
		_go_down(true, false)
		return
	var unaware := state in [S.ROBBING, S.PATROL] or state == S.SCRIPTED
	hp -= float(info.get("amount", 40.0))
	if hp <= 0.0:
		_go_down(true, false)  # дубинка не убивает — сразу арест
		return
	stunned_by_stealth = unaware
	_release_token()
	_release_cover()
	_set_crouched(true)
	_set_state(S.STUNNED)
	_state_timer = 3.5 if unaware else 2.0


# ======================================================================
# Цикл
# ======================================================================

func _physics_process(delta: float) -> void:
	if state == S.DOWN:
		return
	_t += delta
	_think -= delta
	_shot_cd -= delta
	_flinch = maxf(0.0, _flinch - delta)
	velocity.x = 0.0
	velocity.z = 0.0
	if _alert_delay >= 0.0:
		_alert_delay -= delta
		if _alert_delay < 0.0:
			become_alert(_pending_alert_pos)
	match state:
		S.ROBBING:
			_st_robbing(delta)
		S.PATROL:
			_st_patrol(delta)
		S.MOVE_TO_COVER:
			_st_move_to_cover(delta)
		S.IN_COVER:
			_st_in_cover(delta)
		S.PEEK:
			_st_peek(delta)
		S.BLIND_FIRE:
			_st_blind_fire(delta)
		S.RELOAD:
			_st_reload(delta)
		S.ADVANCE:
			_st_advance(delta)
		S.STUNNED:
			_st_stunned(delta)
	if state != S.SCRIPTED:
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
	if _mark_t > 0.0:
		_mark_t -= delta
		if _mark_t <= 0.0:
			_alert_mark.visible = false


func _set_state(s: S) -> void:
	state = s
	_t = 0.0
	_think = 0.0
	match s:
		S.ROBBING:
			_set_crouched(false)
			rig.play("threaten" if role == "threaten" else "idle")
		S.PATROL:
			_set_crouched(false)
			rig.play("walk")
		S.MOVE_TO_COVER:
			_set_crouched(false)
			rig.play("run", 0.12)
			_stuck_t = 0.0
		S.IN_COVER:
			if cover and cover.kind == "low":
				_set_crouched(true)
				rig.play("cover", 0.2)
			else:
				_set_crouched(false)
				rig.play("aim", 0.2)
			_state_timer = float(_d["cover_min"]) * _rng.randf_range(0.8, 1.6)
		S.PEEK:
			_aim_t = float(_d["aim"]) * _rng.randf_range(0.8, 1.3)
			_shots_left = _rng.randi_range(1, 3)
			_peek_saw = false
			if cover == null or cover.kind == "low":
				_set_crouched(false)
				rig.play("aim", 0.12)
		S.BLIND_FIRE:
			_set_crouched(true)
			_shots_left = _rng.randi_range(2, 3)
			rig.play("cover_blind", 0.1)
		S.RELOAD:
			rig.play("c_reload" if _crouched else "reload", 0.15)
			_state_timer = 2.0
			Sfx.play_at("reload_out", eye_position(), -4.0)
		S.ADVANCE:
			_set_crouched(false)
			_state_timer = 1.5
			_aim_t = float(_d["aim"]) * _rng.randf_range(0.9, 1.4)
			rig.play("run", 0.12)
		S.STUNNED:
			rig.play("stunned", 0.1)
		S.DOWN:
			pass


# ---------------------------------------------------------------- мирные состояния

func _st_robbing(delta: float) -> void:
	_face_yaw(home_yaw, delta, 4.0)
	_perceive(delta)


func _st_patrol(delta: float) -> void:
	_perceive(delta)
	if patrol_points.is_empty():
		_set_state(S.ROBBING)
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		rig.play("idle")
		return
	var target := patrol_points[_patrol_i]
	if _move_to(target, 1.4, delta):
		_patrol_i = (_patrol_i + 1) % patrol_points.size()
		_patrol_wait = _rng.randf_range(1.0, 2.5)
	else:
		rig.play("walk")


## Восприятие: конус обзора + линия видимости; «шкала подозрения» растёт быстрее вблизи.
func _perceive(delta: float) -> void:
	_perceive_t -= delta
	if _perceive_t > 0.0:
		awareness = maxf(0.0, awareness - 0.15 * delta)
		return
	_perceive_t = 0.15
	if not _player_ok():
		return
	var eye := eye_position()
	var target: Vector3 = player.chest_position()
	var to := target - eye
	var dist := to.length()
	if dist > VIEW_DIST:
		return
	var fwd := -global_transform.basis.z
	var flat := Vector3(to.x, 0, to.z).normalized()
	if fwd.dot(flat) < VIEW_FOV_COS and dist > 2.0:
		return
	if not _sees_player_from(eye):
		return
	var rate := 2.2 if dist < 5.0 else (1.1 if dist < 11.0 else 0.55)
	if player.crouched:
		rate *= 0.55
	rate *= float(mission.visibility_factor) if mission else 1.0
	awareness += rate * 0.15 / maxf(float(_d["react"]), 0.2) * 0.6
	if awareness >= 1.0:
		become_alert(player.global_position)


# ---------------------------------------------------------------- бой

func _choose_cover_or_advance() -> void:
	_release_cover()
	var c: CoverPoint = null
	if mission and _player_ok():
		c = mission.find_cover(self, player.head_position())
	if c:
		cover = c
		c.claimed_by = self
		_set_state(S.MOVE_TO_COVER)
	else:
		_set_state(S.ADVANCE)


func _st_move_to_cover(delta: float) -> void:
	if cover == null:
		_choose_cover_or_advance()
		return
	if _move_to(cover.position, _speed, delta):
		_set_state(S.IN_COVER)
		return
	_stuck_t += delta
	if _stuck_t > 7.0:
		_choose_cover_or_advance()
		return
	# Игрок вплотную и на виду — огрызнуться на бегу.
	if _player_ok() and _shot_cd <= 0.0 and global_position.distance_to(player.global_position) < 5.0 \
			and _sees_player_from(eye_position()):
		_face_point(player.global_position, delta, 12.0)
		_fire(eye_position() + Vector3(0, -0.1, 0), 1.8)
		_shot_cd = 0.6


func _st_in_cover(delta: float) -> void:
	if cover == null:
		_choose_cover_or_advance()
		return
	# Лицом к угрозе (к укрытию).
	_face_dir(cover.protect_dir, delta, 6.0)
	if cover.kind != "low":
		# За высоким укрытием держимся точно на точке.
		if global_position.distance_to(cover.position) > 0.3:
			_move_to(cover.position, 2.0, delta)
	if _think > 0.0:
		return
	_think = 0.25
	if not _player_ok():
		return
	if not _cover_still_good():
		# Обошли с фланга: если враг рядом и виден — выстрел, затем смена позиции.
		if _shot_cd <= 0.0 and _sees_player_from(eye_position()):
			_face_point(player.global_position, 1.0, 1.0)
			_fire(eye_position(), 1.5)
			_shot_cd = 0.5
		_choose_cover_or_advance()
		return
	if _t < _state_timer:
		return
	if ammo <= 0:
		_set_state(S.RELOAD)
		return
	if not mission.request_token(self):
		_state_timer = _t + 0.5
		return
	_has_token = true
	var space := get_world_3d().direct_space_state
	if cover.peek_sees(space, player.head_position()) or cover.peek_sees(space, player.chest_position()):
		_set_state(S.PEEK)
	elif cover.kind == "low" and _rng.randf() < 0.55 and _blind_misses < 3:
		_set_state(S.BLIND_FIRE)
	else:
		# Из этого укрытия не достать — сменить позицию.
		_release_token()
		_choose_cover_or_advance()


func _st_peek(delta: float) -> void:
	if not _player_ok():
		_end_attack()
		return
	if cover and cover.kind == "high":
		if not _move_to(cover.peek_position(), 2.6, delta) and _t < 1.5:
			rig.play("walk")
			return
		rig.play("aim", 0.1)
	_face_point(player.global_position, delta, 10.0)
	var sees := _sees_player_from(eye_position())
	if sees:
		_peek_saw = true
	if _flinch > 0.0:
		return
	if _aim_t > 0.0:
		_aim_t -= delta
		return
	if _shot_cd > 0.0:
		return
	if sees and _shots_left > 0:
		_fire(eye_position(), 1.0)
		_shots_left -= 1
		_shot_cd = _rng.randf_range(0.22, 0.38)
	elif not sees and _t > 0.9:
		_shots_left = 0
	if _shots_left <= 0 or ammo <= 0:
		_end_attack()


func _st_blind_fire(delta: float) -> void:
	if cover:
		_face_dir(cover.protect_dir, delta, 8.0)
	if _shot_cd > 0.0:
		return
	if _shots_left > 0 and ammo > 0 and _player_ok():
		# Рука над укрытием: огонь без прицеливания по примерной позиции.
		var origin := global_position + Vector3(0, 1.4, 0) + (cover.protect_dir if cover else Vector3.ZERO) * 0.3
		if _fire(origin, 4.0):
			_blind_misses = 0
		else:
			_blind_misses += 1
		_shots_left -= 1
		_shot_cd = _rng.randf_range(0.25, 0.4)
		rig.play("cover_blind", 0.05, 1.0, true)
	else:
		_end_attack()


func _end_attack() -> void:
	_release_token()
	if ammo <= 0:
		_set_state(S.RELOAD)
	elif cover and _player_ok() and cover.protects(get_world_3d().direct_space_state, player.head_position()):
		_set_state(S.IN_COVER)
	else:
		_choose_cover_or_advance()


func _st_reload(_delta: float) -> void:
	if _t >= _state_timer:
		ammo = mag_size
		Sfx.play_at("reload_in", eye_position(), -4.0)
		if cover:
			_set_state(S.IN_COVER)
		else:
			_choose_cover_or_advance()


## Нет укрытия: сближение до дистанции огня, стрельба стоя, периодический поиск укрытия.
func _st_advance(delta: float) -> void:
	if not _player_ok():
		return
	var ppos: Vector3 = player.global_position
	var dist := global_position.distance_to(ppos)
	var sees := _sees_player_from(eye_position())
	if sees and dist < 11.0:
		_face_point(ppos, delta, 10.0)
		rig.play("aim", 0.1)
		if _aim_t > 0.0:
			_aim_t -= delta
		elif _shot_cd <= 0.0 and ammo > 0:
			if _has_token or mission.request_token(self):
				_has_token = true
				_fire(eye_position(), 1.2)
				_shot_cd = _rng.randf_range(0.35, 0.6)
	else:
		_release_token()
		_move_to(ppos, _speed * 0.85, delta)
		rig.play("run")
	if ammo <= 0:
		_release_token()
		_set_state(S.RELOAD)
		return
	if _t > _state_timer:
		_t = 0.0
		_state_timer = 1.5
		var c: CoverPoint = mission.find_cover(self, player.head_position())
		if c:
			_release_token()
			_release_cover()
			cover = c
			c.claimed_by = self
			_set_state(S.MOVE_TO_COVER)


func _st_stunned(_delta: float) -> void:
	if _t >= _state_timer:
		_set_crouched(false)
		stunned_by_stealth = false
		awareness = 1.0
		_choose_cover_or_advance()


# ======================================================================
# Стрельба
# ======================================================================

## Выстрел в игрока. Возвращает true при попадании.
func _fire(origin: Vector3, spread_mult: float) -> bool:
	if ammo <= 0 or not _player_ok():
		return false
	ammo -= 1
	var target: Vector3 = player.chest_position() if _rng.randf() < 0.8 else player.head_position()
	var dir := (target - origin).normalized()
	var dist := origin.distance_to(target)
	var spread := float(_d["spread"]) * spread_mult * (1.0 + dist / 18.0)
	if player.velocity.length() > 1.5:
		spread *= 1.35
	dir = Combat.spread_dir(dir, spread, _rng)
	var to := origin + dir * 60.0
	var space := get_world_3d().direct_space_state
	var hit := Combat.ray(space, origin, to, Combat.MASK_BANDIT_BULLET, [get_rid()])
	var end := to
	var hit_player := false
	if not hit.is_empty():
		end = hit["position"]
		if hit["collider"] == player:
			hit_player = true
			player.apply_damage({"amount": float(_d["dmg"]) * _dmg_mult, "from": global_position, "kind": "bullet"})
		elif mission:
			mission.fx.impact(hit["position"], hit["normal"])
			Sfx.play_at("impact", hit["position"], -8.0)
	if not hit_player and player.has_method("near_miss"):
		if Combat.point_segment_distance(player.head_position(), origin, end) < 1.0:
			player.near_miss(global_position)
	var muzzle := rig.muzzle_position()
	if mission:
		mission.fx.tracer(muzzle, end)
		mission.fx.flash(muzzle)
		mission.noise(global_position, 15.0)
	Sfx.play_at("shot_enemy", muzzle, 2.0)
	if state != S.BLIND_FIRE:
		rig.play("c_shoot" if _crouched else "shoot", 0.03, 1.0, true)
	return hit_player


# ======================================================================
# Вспомогательное
# ======================================================================

func _player_ok() -> bool:
	return player != null and is_instance_valid(player) and player.alive


func _sees_player_from(eye: Vector3) -> bool:
	if not _player_ok():
		return false
	var space := get_world_3d().direct_space_state
	return Combat.line_clear(space, eye, player.head_position()) or Combat.line_clear(space, eye, player.chest_position())


func _cover_still_good() -> bool:
	if cover == null or not _player_ok():
		return false
	return cover.protects(get_world_3d().direct_space_state, player.head_position())


func _release_token() -> void:
	if _has_token and mission:
		mission.release_token(self)
	_has_token = false


func _release_cover() -> void:
	if cover and cover.claimed_by == self:
		cover.claimed_by = null
	cover = null


func _set_crouched(c: bool) -> void:
	if c == _crouched:
		return
	_crouched = c
	_capsule.height = CROUCH_H if c else STAND_H
	_shape.position.y = _capsule.height / 2.0


func _go_down(arrested: bool, headshot: bool) -> void:
	_release_token()
	_release_cover()
	state = S.DOWN
	hp = maxf(hp, 0.0)
	collision_layer = 0
	collision_mask = 0
	_alert_mark.visible = false
	velocity = Vector3.ZERO
	rig.play("arrested" if arrested else "death", 0.08)
	neutralized.emit(self, arrested, headshot)


func _show_alert_mark() -> void:
	_alert_mark.visible = true
	_mark_t = 1.2


## Движение по навмешу. Возвращает true, когда точка достигнута.
func _move_to(target: Vector3, speed: float, delta: float) -> bool:
	var flat_dist := Vector2(global_position.x - target.x, global_position.z - target.z).length()
	if flat_dist < 0.35:
		return true
	if agent.target_position.distance_to(target) > 0.25:
		agent.target_position = target
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		# Навмеш ещё не готов или путь кончился рядом с целью — идём напрямую.
		dir = target - global_position
		dir.y = 0.0
		if agent.is_navigation_finished() and flat_dist < 0.8:
			return true
	if dir.length() < 0.001:
		return true
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face_dir(dir, delta, 10.0)
	return false


func _face_dir(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length_squared() < 0.0001:
		return
	_face_yaw(Combat.yaw_from_dir(dir), delta, rate)


func _face_point(p: Vector3, delta: float, rate: float) -> void:
	_face_dir(p - global_position, delta, rate)


func _face_yaw(yaw: float, delta: float, rate: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rate * delta, 0.0, 1.0))
