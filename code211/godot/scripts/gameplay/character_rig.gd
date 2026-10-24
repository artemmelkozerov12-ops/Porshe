class_name CharacterRig
extends Node3D
## Модель персонажа + набор анимаций.
##
## Порядок загрузки:
##   1) res://assets/models/<kind>.glb из Blender-пайплайна (blender/build_all.py),
##      если в нём есть AnimationPlayer со всеми обязательными клипами;
##   2) иначе — процедурная low-poly модель с теми же именами костей и анимаций.
## Так игра запускается всегда, а модели из Blender подменяют заглушки без правок кода.
##
## Соглашение по осям: персонаж смотрит в -Z, «кости» — узлы-шарниры (pivot),
## положительный поворот по X поднимает конечность вперёд.

const REQUIRED_ANIMS := ["idle", "walk", "run", "aim", "shoot", "reload", "cover", "hit", "death"]

const LOOPING := ["idle", "idle_unarmed", "walk", "run", "aim", "cover", "c_aim", "hands_up",
	"threaten", "stunned", "cower"]

const LOOKS := {
	"cop": {"top": Color("1f2d4d"), "bottom": Color("161d2c"), "head": Color("c69c7b"),
		"shoes": Color("101010"), "armed": true, "gear": "cop"},
	"bandit_light": {"top": Color("3b4048"), "bottom": Color("2d3953"), "head": Color("151515"),
		"shoes": Color("d8d8d8"), "armed": true, "gear": "mask"},
	"bandit_medium": {"top": Color("33352f"), "bottom": Color("2b2f26"), "head": Color("151515"),
		"shoes": Color("2a2a2a"), "armed": true, "gear": "vest"},
	"bandit_heavy": {"top": Color("232528"), "bottom": Color("1d1f22"), "head": Color("151515"),
		"shoes": Color("1a1a1a"), "armed": true, "gear": "heavy"},
	"cashier": {"top": Color("b8323a"), "bottom": Color("2b2f3a"), "head": Color("d1a684"),
		"shoes": Color("2a2a2a"), "armed": false, "gear": "apron"},
	"customer": {"top": Color("6b5b45"), "bottom": Color("39404d"), "head": Color("b88a68"),
		"shoes": Color("4a3a2a"), "armed": false, "gear": ""},
}

const SKIN := Color("c69c7b")
const PIVOTS := ["hips", "spine", "neck", "shoulder_l", "elbow_l", "shoulder_r", "elbow_r",
	"hip_l", "knee_l", "hip_r", "knee_r"]

var kind := "bandit_light"
var anim: AnimationPlayer
var muzzle: Node3D
var using_imported := false
var _paths: Dictionary = {}   # имя шарнира -> NodePath относительно рига
var _nodes: Dictionary = {}   # имя шарнира -> Node3D
var _current := ""
var _layers := Combat.VIS_INTERIOR


func setup(p_kind: String, layers: int = Combat.VIS_INTERIOR) -> void:
	kind = p_kind if LOOKS.has(p_kind) else "bandit_light"
	_layers = layers
	if not _try_load_imported():
		_build_procedural()
		_build_animations()
	if muzzle == null:
		muzzle = Node3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0.2, 1.45, -0.55)
		add_child(muzzle)


func is_armed() -> bool:
	return bool(LOOKS[kind]["armed"])


## Проиграть клип. restart=true — перезапустить, даже если он уже играет (выстрел).
func play(clip: String, blend: float = 0.15, speed: float = 1.0, restart: bool = false) -> void:
	if anim == null:
		return
	if not anim.has_animation(clip):
		clip = _fallback(clip)
		if not anim.has_animation(clip):
			return
	if clip == _current and anim.is_playing() and not restart:
		return
	_current = clip
	anim.play(clip, blend, speed)
	if restart:
		anim.seek(0.0, true)


func current() -> String:
	return _current


func muzzle_position() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position + Vector3(0, 1.4, 0)


func _fallback(clip: String) -> String:
	if clip.begins_with("c_"):
		return clip.substr(2)
	match clip:
		"idle_unarmed", "hands_up", "cower", "threaten", "stunned":
			return "idle"
		"arrested":
			return "death"
		"cover_blind":
			return "cover"
	return "idle"


# ======================================================================
# Импорт модели из Blender-пайплайна
# ======================================================================

func _try_load_imported() -> bool:
	var path := "res://assets/models/%s.glb" % kind
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("CharacterRig: %s не загрузился, использую процедурную модель" % path)
		return false
	var inst := scene.instantiate()
	var player := _find_anim_player(inst)
	if player == null:
		inst.free()
		push_warning("CharacterRig: в %s нет AnimationPlayer" % path)
		return false
	for req in REQUIRED_ANIMS:
		if not player.has_animation(req):
			inst.free()
			push_warning("CharacterRig: в %s нет клипа '%s'" % [path, req])
			return false
	add_child(inst)
	_set_layers_recursive(inst, _layers)
	for clip in LOOPING:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim = player
	var m := inst.find_child("Muzzle", true, false)
	if m is Node3D:
		muzzle = m
	using_imported = true
	return true


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


func _set_layers_recursive(n: Node, layers: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layers
	for c in n.get_children():
		_set_layers_recursive(c, layers)


# ======================================================================
# Процедурная модель
# ======================================================================

func _pivot(pivot_name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pivot_name
	p.position = pos
	parent.add_child(p)
	_nodes[pivot_name] = p
	_paths[pivot_name] = NodePath(str(get_path_to(p)))
	return p


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float = 0.85) -> MeshInstance3D:
	return Mats.add_mesh(parent, Mats.box(size), Mats.solid(color, rough), pos, Vector3.ZERO, _layers)


func _build_procedural() -> void:
	var look: Dictionary = LOOKS[kind]
	var top: Color = look["top"]
	var bottom: Color = look["bottom"]
	var head_c: Color = look["head"]
	var shoes: Color = look["shoes"]
	var gear: String = look["gear"]
	var skin := SKIN if gear != "apron" else Color("d1a684")

	var hips := _pivot("hips", self, Vector3(0, 0.95, 0))
	_part(hips, Vector3(0.34, 0.18, 0.2), Vector3.ZERO, bottom)
	var spine := _pivot("spine", hips, Vector3(0, 0.08, 0))
	_part(spine, Vector3(0.4, 0.5, 0.24), Vector3(0, 0.27, 0), top)
	var neck := _pivot("neck", spine, Vector3(0, 0.52, 0))
	_part(neck, Vector3(0.1, 0.08, 0.1), Vector3(0, 0.03, 0), head_c if gear in ["mask", "vest", "heavy"] else skin)
	_part(neck, Vector3(0.22, 0.25, 0.24), Vector3(0, 0.17, 0), head_c if gear in ["mask", "vest", "heavy"] else skin)

	match gear:
		"cop":
			_part(neck, Vector3(0.25, 0.07, 0.27), Vector3(0, 0.31, 0.0), Color("18233d"))
			_part(neck, Vector3(0.24, 0.02, 0.1), Vector3(0, 0.28, -0.16), Color("101010"), 0.3)
			_part(neck, Vector3(0.05, 0.05, 0.01), Vector3(0, 0.32, -0.14), Color("d4a93a"), 0.3)
			_part(spine, Vector3(0.06, 0.07, 0.01), Vector3(-0.1, 0.38, -0.125), Color("d4a93a"), 0.3)  # жетон
			_part(hips, Vector3(0.36, 0.06, 0.22), Vector3(0, 0.07, 0), Color("0e0e0e"), 0.4)          # ремень
			_part(spine, Vector3(0.36, 0.03, 0.02), Vector3(0, 0.46, -0.125), Color("2a3a5e"))
		"mask", "vest", "heavy":
			_part(neck, Vector3(0.2, 0.05, 0.02), Vector3(0, 0.2, -0.12), skin)                         # прорезь балаклавы
			_part(neck, Vector3(0.14, 0.02, 0.005), Vector3(0, 0.2, -0.131), Color("1a1a1a"))
			if gear == "vest" or gear == "heavy":
				var vest_c := Color("4a5236") if gear == "vest" else Color("2e3328")
				var thick := 0.32 if gear == "vest" else 0.36
				_part(spine, Vector3(0.44, 0.4, thick), Vector3(0, 0.3, 0), vest_c)
				_part(spine, Vector3(0.3, 0.1, 0.06), Vector3(0, 0.18, -thick * 0.5 - 0.02), vest_c.darkened(0.2))
			if gear == "heavy":
				_part(neck, Vector3(0.27, 0.13, 0.29), Vector3(0, 0.28, 0.0), Color("3b4031"))        # шлем
				_part(neck, Vector3(0.22, 0.06, 0.02), Vector3(0, 0.22, -0.145), Color("101418"), 0.2)  # визор
		"apron":
			_part(spine, Vector3(0.38, 0.5, 0.02), Vector3(0, 0.15, -0.13), Color("2f6b4f"))
			_part(neck, Vector3(0.23, 0.08, 0.25), Vector3(0, 0.29, 0.01), Color("3a2a1e"))          # волосы
		_:
			_part(neck, Vector3(0.23, 0.07, 0.25), Vector3(0, 0.29, 0.01), Color("2a2018"))

	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sh := _pivot("shoulder_" + s, spine, Vector3(0.26 * side, 0.46, 0))
		_part(sh, Vector3(0.11, 0.3, 0.12), Vector3(0, -0.14, 0), top)
		if gear == "heavy":
			_part(sh, Vector3(0.15, 0.12, 0.16), Vector3(0, -0.02, 0), Color("2e3328"))
		var el := _pivot("elbow_" + s, sh, Vector3(0, -0.29, 0))
		_part(el, Vector3(0.1, 0.27, 0.1), Vector3(0, -0.13, 0), top if kind != "cop" else top.lightened(0.05))
		_part(el, Vector3(0.09, 0.1, 0.1), Vector3(0, -0.31, 0), skin if gear != "heavy" else Color("151515"))
		if s == "r" and bool(look["armed"]):
			_attach_pistol(el, gear == "heavy")

		var hp := _pivot("hip_" + s, hips, Vector3(0.1 * side, -0.05, 0))
		_part(hp, Vector3(0.15, 0.44, 0.16), Vector3(0, -0.22, 0), bottom)
		var kn := _pivot("knee_" + s, hp, Vector3(0, -0.44, 0))
		_part(kn, Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), bottom)
		_part(kn, Vector3(0.13, 0.08, 0.25), Vector3(0, -0.44, -0.05), shoes)


func _attach_pistol(elbow: Node3D, long_gun: bool) -> void:
	# Сокет в кисти: его -Z совпадает с направлением вытянутой руки, +Y — «верх» оружия.
	var socket := Node3D.new()
	socket.name = "WeaponSocket"
	socket.position = Vector3(0, -0.33, 0)
	socket.rotation = Vector3(-PI / 2.0, 0, 0)
	elbow.add_child(socket)
	var dark := Color("1b1c1f")
	if long_gun:
		_part(socket, Vector3(0.05, 0.07, 0.5), Vector3(0, 0.03, -0.18), dark, 0.5)
		_part(socket, Vector3(0.04, 0.12, 0.05), Vector3(0, -0.04, 0.02), Color("3a2c22"), 0.6)
	else:
		_part(socket, Vector3(0.04, 0.05, 0.19), Vector3(0, 0.03, -0.06), dark, 0.4)
		_part(socket, Vector3(0.035, 0.1, 0.05), Vector3(0, -0.03, 0.02), dark, 0.6)
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.03, -0.45 if long_gun else -0.18)
	socket.add_child(muzzle)


# ======================================================================
# Анимации (ключевые позы → Animation с треками rotation по шарнирам)
# ======================================================================

## Базовые позы. Отсутствующие шарниры = ноль. "hips_y" — высота таза.
func _pose(overrides: Dictionary) -> Dictionary:
	var p := {"hips_y": 0.95}
	for k in PIVOTS:
		p[k] = Vector3.ZERO
	for k in overrides:
		p[k] = overrides[k]
	return p


func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	for k in over:
		p[k] = over[k]
	return p


func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	var lib := AnimationLibrary.new()

	var arms_ready := {
		"shoulder_r": Vector3(0.65, 0, -0.05), "elbow_r": Vector3(0.55, 0, 0),
		"shoulder_l": Vector3(0.55, 0, 0.3), "elbow_l": Vector3(0.75, 0, 0),
	}
	var arms_aim := {
		"shoulder_r": Vector3(1.5, 0, -0.08), "elbow_r": Vector3(0.0, 0, 0),
		"shoulder_l": Vector3(1.4, 0, 0.42), "elbow_l": Vector3(0.15, 0, 0),
		"spine": Vector3(-0.04, 0, 0),
	}
	var arms_relaxed := {
		"shoulder_r": Vector3(0.05, 0, -0.08), "shoulder_l": Vector3(0.05, 0, 0.08),
		"elbow_r": Vector3(0.15, 0, 0), "elbow_l": Vector3(0.15, 0, 0),
	}
	var crouch_legs := {
		"hips_y": 0.47, "spine": Vector3(-0.45, 0, 0), "neck": Vector3(0.25, 0, 0),
		"hip_l": Vector3(1.6, 0, 0.05), "knee_l": Vector3(-2.2, 0, 0),
		"hip_r": Vector3(1.3, 0, -0.05), "knee_r": Vector3(-2.05, 0, 0),
	}
	var armed := is_armed()
	var upper_idle: Dictionary = arms_ready if armed else arms_relaxed

	var idle_a := _pose(upper_idle)
	var idle_b := _merge(idle_a, {"spine": Vector3(0.03, 0, 0), "hips_y": 0.945})
	_clip(lib, "idle", 2.0, [[0.0, idle_a], [1.0, idle_b], [2.0, idle_a]])
	var un_a := _pose(arms_relaxed)
	_clip(lib, "idle_unarmed", 2.0, [[0.0, un_a], [1.0, _merge(un_a, {"spine": Vector3(0.03, 0, 0)})], [2.0, un_a]])

	# Ходьба/бег: противофаза ног, «отскок» таза.
	for spec in [["walk", 0.9, 0.45, -0.65, 0.93, 0.0], ["run", 0.6, 0.8, -1.25, 0.9, -0.22]]:
		var clip_name: String = spec[0]
		var period: float = spec[1]
		var swing: float = spec[2]
		var knee: float = spec[3]
		var low: float = spec[4]
		var lean: float = spec[5]
		var upper: Dictionary = upper_idle.duplicate()
		if not armed:
			upper = {}
		var keys := []
		for i in 5:
			var ph := float(i) / 4.0
			var s := sin(ph * TAU)
			var c := cos(ph * TAU)
			var p := _pose(upper)
			p["hip_l"] = Vector3(swing * s, 0, 0)
			p["hip_r"] = Vector3(-swing * s, 0, 0)
			p["knee_l"] = Vector3(knee * maxf(0.0, -c), 0, 0)
			p["knee_r"] = Vector3(knee * maxf(0.0, c), 0, 0)
			p["hips_y"] = lerpf(0.95, low, absf(s))
			p["spine"] = Vector3(lean, 0, 0)
			if not armed:
				p["shoulder_l"] = Vector3(-swing * 0.7 * s, 0, 0.08)
				p["shoulder_r"] = Vector3(swing * 0.7 * s, 0, -0.08)
				p["elbow_l"] = Vector3(0.3, 0, 0)
				p["elbow_r"] = Vector3(0.3, 0, 0)
			keys.append([ph * period, p])
		_clip(lib, clip_name, period, keys)

	var aim := _pose(arms_aim)
	_clip(lib, "aim", 1.6, [[0.0, aim], [0.8, _merge(aim, {"spine": Vector3(-0.02, 0, 0)})], [1.6, aim]])
	var kick := _merge(aim, {"shoulder_r": Vector3(1.78, 0, -0.08), "elbow_r": Vector3(0.2, 0, 0),
		"shoulder_l": Vector3(1.62, 0, 0.42), "spine": Vector3(0.04, 0, 0)})
	_clip(lib, "shoot", 0.22, [[0.0, aim], [0.05, kick], [0.22, aim]])
	var low_r := _merge(aim, {"shoulder_r": Vector3(0.75, 0, -0.1), "elbow_r": Vector3(1.1, 0, 0),
		"shoulder_l": Vector3(0.9, 0, 0.35), "elbow_l": Vector3(1.3, 0, 0)})
	var fetch := _merge(low_r, {"shoulder_l": Vector3(0.15, 0, 0.15), "elbow_l": Vector3(0.4, 0, 0)})
	_clip(lib, "reload", 1.6, [[0.0, aim], [0.3, low_r], [0.65, fetch], [1.05, low_r], [1.6, aim]])
	var hit := _merge(aim, {"spine": Vector3(0.38, 0, 0.1), "neck": Vector3(0.3, 0, 0),
		"shoulder_l": Vector3(0.6, 0, 0.5)})
	_clip(lib, "hit", 0.32, [[0.0, aim], [0.08, hit], [0.32, aim]])

	# Варианты «в приседе» для боя из-за низкого укрытия.
	var c_aim := _merge(aim, crouch_legs)
	_clip(lib, "c_aim", 1.6, [[0.0, c_aim], [1.6, c_aim]])
	_clip(lib, "c_shoot", 0.22, [[0.0, c_aim], [0.05, _merge(kick, crouch_legs)], [0.22, c_aim]])
	_clip(lib, "c_reload", 1.6, [[0.0, c_aim], [0.3, _merge(low_r, crouch_legs)],
		[0.65, _merge(fetch, crouch_legs)], [1.05, _merge(low_r, crouch_legs)], [1.6, c_aim]])
	_clip(lib, "c_hit", 0.32, [[0.0, c_aim], [0.08, _merge(hit, crouch_legs)], [0.32, c_aim]])
	var cover := _merge(_pose({"shoulder_r": Vector3(0.9, 0, -0.25), "elbow_r": Vector3(1.4, 0, 0),
		"shoulder_l": Vector3(0.8, 0, 0.35), "elbow_l": Vector3(1.3, 0, 0)}), crouch_legs)
	_clip(lib, "cover", 2.0, [[0.0, cover], [1.0, _merge(cover, {"neck": Vector3(0.35, 0.15, 0)})], [2.0, cover]])
	var blind := _merge(cover, {"shoulder_r": Vector3(2.6, 0, -0.1), "elbow_r": Vector3(-1.0, 0, 0)})
	var blind_k := _merge(blind, {"shoulder_r": Vector3(2.75, 0, -0.1)})
	_clip(lib, "cover_blind", 0.3, [[0.0, blind], [0.06, blind_k], [0.3, blind]])

	# Смерть: падение навзничь (таз поворачивается и опускается).
	var d1 := _merge(hit, {"hips_y": 0.75, "spine": Vector3(0.5, 0, 0), "knee_l": Vector3(-0.6, 0, 0),
		"knee_r": Vector3(-0.4, 0, 0)})
	var d2 := _pose({"hips_y": 0.17, "hips": Vector3(1.48, 0, 0.05), "spine": Vector3(0.1, 0, 0),
		"neck": Vector3(0.2, 0.4, 0), "shoulder_l": Vector3(0.3, 0, 1.2), "shoulder_r": Vector3(0.6, 0, -1.3),
		"elbow_l": Vector3(0.4, 0, 0), "elbow_r": Vector3(0.6, 0, 0), "hip_l": Vector3(0.1, 0, 0.15),
		"knee_l": Vector3(-0.3, 0, 0), "hip_r": Vector3(0.35, 0, -0.1), "knee_r": Vector3(-0.6, 0, 0)})
	_clip(lib, "death", 1.1, [[0.0, aim], [0.25, d1], [0.9, d2], [1.1, d2]])

	# Арест: на коленях, руки за головой.
	var kneel := _pose({"hips_y": 0.5, "hip_l": Vector3(0.0, 0, 0.05), "knee_l": Vector3(-1.55, 0, 0),
		"hip_r": Vector3(0.0, 0, -0.05), "knee_r": Vector3(-1.55, 0, 0), "spine": Vector3(-0.1, 0, 0),
		"neck": Vector3(0.3, 0, 0), "shoulder_l": Vector3(0.3, 0, -2.5), "elbow_l": Vector3(0, 0, 2.3),
		"shoulder_r": Vector3(0.3, 0, 2.5), "elbow_r": Vector3(0, 0, -2.3)})
	_clip(lib, "arrested", 1.0, [[0.0, hit], [0.6, kneel], [1.0, kneel]])
	var stun := _merge(crouch_legs, {"spine": Vector3(-0.7, 0, 0), "shoulder_l": Vector3(2.3, 0, 0.5),
		"elbow_l": Vector3(1.9, 0, 0), "shoulder_r": Vector3(2.3, 0, -0.5), "elbow_r": Vector3(1.9, 0, 0)})
	var stun_p := _pose(stun)
	_clip(lib, "stunned", 1.2, [[0.0, stun_p], [0.6, _merge(stun_p, {"spine": Vector3(-0.6, 0.15, 0.1)})], [1.2, stun_p]])

	var hands_up := _pose({"shoulder_l": Vector3(0.1, 0, -2.75), "elbow_l": Vector3(0, 0, -0.25),
		"shoulder_r": Vector3(0.1, 0, 2.75), "elbow_r": Vector3(0, 0, 0.25), "neck": Vector3(0.1, 0, 0)})
	_clip(lib, "hands_up", 1.4, [[0.0, hands_up], [0.7, _merge(hands_up, {"spine": Vector3(0.05, 0, 0)})], [1.4, hands_up]])
	var cower := _pose(_merge(crouch_legs, {"spine": Vector3(-0.8, 0, 0), "shoulder_l": Vector3(2.4, 0, 0.6),
		"elbow_l": Vector3(2.0, 0, 0), "shoulder_r": Vector3(2.4, 0, -0.6), "elbow_r": Vector3(2.0, 0, 0)}))
	_clip(lib, "cower", 1.0, [[0.0, cower], [0.5, _merge(cower, {"spine": Vector3(-0.75, 0, 0)})], [1.0, cower]])
	var jab := _merge(aim, {"shoulder_r": Vector3(1.62, 0, -0.08), "spine": Vector3(-0.1, 0, 0)})
	_clip(lib, "threaten", 1.2, [[0.0, aim], [0.3, jab], [0.6, aim], [1.2, aim]])

	anim.add_animation_library("", lib)


## keys: [[время, поза], ...]. В каждом клипе ключуются ВСЕ шарниры — нет «залипших» поз при смешивании.
func _clip(lib: AnimationLibrary, clip_name: String, length: float, keys: Array) -> void:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING else Animation.LOOP_NONE
	for pv in PIVOTS:
		var tr := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(tr, NodePath(str(_paths[pv]) + ":rotation"))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC if a.loop_mode != Animation.LOOP_NONE else Animation.INTERPOLATION_LINEAR)
		a.value_track_set_update_mode(tr, Animation.UPDATE_CONTINUOUS)
		for k in keys:
			var pose: Dictionary = k[1]
			a.track_insert_key(tr, float(k[0]), pose.get(pv, Vector3.ZERO))
	var ht := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(ht, NodePath(str(_paths["hips"]) + ":position:y"))
	a.value_track_set_update_mode(ht, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		var pose2: Dictionary = k[1]
		a.track_insert_key(ht, float(k[0]), float(pose2.get("hips_y", 0.95)))
	lib.add_animation(clip_name, a)
