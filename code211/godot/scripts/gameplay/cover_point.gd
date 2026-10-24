class_name CoverPoint
extends RefCounted
## Точка укрытия, сгенерированная вокруг реквизита.
##   protect_dir — направление от точки к укрытию (с этой стороны укрытие защищает);
##   kind "low"  — присесть за низким (стеллаж, касса), выглядывать — встать;
##   kind "high" — стоять за колонной/банкоматом, выглядывать — шаг вбок (peek_offset).

const HIDE_HEIGHT_LOW := 0.85
const HIDE_HEIGHT_HIGH := 1.3
const PEEK_EYE := 1.55

var position: Vector3
var protect_dir: Vector3
var kind: String = "low"
var peek_offset: Vector3 = Vector3.ZERO
var claimed_by: Node = null


func _init(p: Vector3, dir: Vector3, k: String, peek: Vector3 = Vector3.ZERO) -> void:
	position = p
	protect_dir = dir.normalized()
	kind = k
	peek_offset = peek


func is_free_for(who: Node) -> bool:
	if claimed_by == null or not is_instance_valid(claimed_by):
		return true
	return claimed_by == who


func hide_point() -> Vector3:
	return position + Vector3(0, HIDE_HEIGHT_LOW if kind == "low" else HIDE_HEIGHT_HIGH, 0)


func peek_position() -> Vector3:
	return position + peek_offset


func peek_eye() -> Vector3:
	return peek_position() + Vector3(0, PEEK_EYE, 0)


## Защищает ли точка от стрелка в `threat`: угроза с «правильной» стороны и линия огня перекрыта.
func protects(space: PhysicsDirectSpaceState3D, threat: Vector3) -> bool:
	var to := threat - position
	to.y = 0.0
	if to.length() < 1.5 or protect_dir.dot(to.normalized()) < 0.2:
		return false
	return not Combat.line_clear(space, threat, hide_point())


## Видно ли угрозу при выглядывании.
func peek_sees(space: PhysicsDirectSpaceState3D, threat: Vector3) -> bool:
	return Combat.line_clear(space, peek_eye(), threat)
