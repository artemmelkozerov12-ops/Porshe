class_name Combat
extends RefCounted
## Общие константы физики и утилиты стрельбы.

# Биты слоёв столкновений (см. project.godot → layer_names).
const L_WORLD := 1
const L_PLAYER := 2
const L_BANDIT := 4
const L_CIVILIAN := 8
const L_GLASS := 16

# Визуальные слои: «внутренние» объекты не освещаются солнцем/луной.
const VIS_EXTERIOR := 1
const VIS_INTERIOR := 2

const MASK_PLAYER_BULLET := L_WORLD | L_BANDIT | L_CIVILIAN
const MASK_BANDIT_BULLET := L_WORLD | L_PLAYER
const MASK_SIGHT := L_WORLD


static func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID] = []) -> Dictionary:
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = false
	q.hit_back_faces = false
	return space.intersect_ray(q)


static func line_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		mask: int = MASK_SIGHT) -> bool:
	return ray(space, from, to, mask).is_empty()


## Случайное направление внутри конуса `deg` градусов вокруг `dir`.
static func spread_dir(dir: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
	if deg <= 0.001:
		return dir
	var a := deg_to_rad(deg) * sqrt(rng.randf())
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	var phi := rng.randf() * TAU
	return (dir + (right * cos(phi) + up2 * sin(phi)) * tan(a)).normalized()


## Расстояние от точки до отрезка (для «пуля просвистела рядом»).
static func point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func yaw_from_dir(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
