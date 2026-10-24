class_name Civilian
extends CharacterBody3D
## Гражданский (кассир / покупатель). Ранение гражданского игроком = провал миссии.
## Пули грабителей гражданских не задевают (их маска без слоя civilians) —
## провал всегда зависит от действий игрока.

signal hurt(civilian: Civilian)

enum S { CALM, HOSTAGE, COWER, SAFE }

var kind := "cashier"
var state: S = S.CALM
var rig: CharacterRig
var home_yaw := 0.0


func setup(cdef: Dictionary) -> void:
	kind = String(cdef.get("kind", "cashier"))
	home_yaw = deg_to_rad(float(cdef.get("face", 0.0)))


func _ready() -> void:
	collision_layer = Combat.L_CIVILIAN
	collision_mask = Combat.L_WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(kind)
	rotation.y = home_yaw
	set_state(S.CALM)


func set_state(s: S) -> void:
	state = s
	match s:
		S.CALM:
			rig.play("idle_unarmed", 0.2)
		S.HOSTAGE:
			rig.play("hands_up", 0.25)
		S.COWER:
			rig.play("cower", 0.25)
		S.SAFE:
			rig.play("idle_unarmed", 0.4)


func apply_damage(info: Dictionary) -> void:
	if not bool(info.get("by_player", false)):
		return
	rig.play("death", 0.05)
	collision_layer = 0
	hurt.emit(self)
