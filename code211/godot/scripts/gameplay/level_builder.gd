class_name LevelBuilder
extends RefCounted
## Строит уровень по описанию из MissionDB: улица, фасад, торговый зал,
## реквизит (стеллажи/кассы/холодильники), свет, окружение, навмеш и укрытия.
##
## Вся статика с коллизиями кладётся внутрь NavigationRegion3D — навмеш
## запекается из её коллайдеров. Товары на полках — один MultiMesh на уровень.

const WALL_H := 3.0
const WALL_T := 0.2
const FACADE_H := 4.6
const DOOR_W := 1.6
const DOOR_H := 2.4
const WIN_BOTTOM := 0.9
const WIN_TOP := 2.45
const STREET_Z := 13.0
const COVER_OFFSET := 0.5

# Габариты реквизита: размер (x, y, z) до поворота и тип укрытия.
const PROPS := {
	"shelf": {"size": Vector3(2.4, 1.35, 0.8), "cover": "low"},
	"shelf_wall": {"size": Vector3(2.4, 2.0, 0.5), "cover": ""},
	"fridge": {"size": Vector3(1.6, 2.1, 0.8), "cover": ""},
	"counter": {"size": Vector3(2.6, 1.05, 0.8), "cover": "low"},
	"crates": {"size": Vector3(1.0, 1.1, 1.0), "cover": "low"},
	"pallet": {"size": Vector3(1.2, 1.4, 1.0), "cover": "low"},
	"freezer": {"size": Vector3(1.8, 0.95, 0.9), "cover": "low"},
	"pillar": {"size": Vector3(0.6, 3.0, 0.6), "cover": "high"},
	"atm": {"size": Vector3(0.7, 1.75, 0.6), "cover": "high"},
	"display": {"size": Vector3(1.0, 1.2, 0.6), "cover": "low"},
}

const GOODS_COLORS := [Color("d9452b"), Color("f2c230"), Color("2f8fd8"), Color("3cb371"), Color("f28c28"),
	Color("eae6da"), Color("8e44ad"), Color("c0392b"), Color("16a085"), Color("e84393"), Color("6c5ce7")]

var def: Dictionary
var W := 14.0
var D := 10.0
var root: Node3D
var region: NavigationRegion3D
var rng := RandomNumberGenerator.new()
var prop_rects: Array = []     # [{center: Vector2, half: Vector2, cover: String}]
var wall_rects: Array = []     # внутренние перегородки
var _goods_xf: Array[Transform3D] = []
var _goods_col: PackedColorArray = PackedColorArray()

# Результат сборки.
var sun: DirectionalLight3D
var env: Environment
var interior_lights: Array[OmniLight3D] = []
var flicker_lights: Array[OmniLight3D] = []
var rain: GPUParticles3D
var covers: Array = []


func build(parent: Node3D, mission_def: Dictionary) -> Node3D:
	def = mission_def
	var sz: Vector2 = def["size"]
	W = sz.x
	D = sz.y
	rng.seed = hash(String(def["id"]))
	root = Node3D.new()
	root.name = "Level"
	parent.add_child(root)
	region = NavigationRegion3D.new()
	region.name = "NavRegion"
	root.add_child(region)

	_environment()
	_ground()
	_store_shell()
	_exterior()
	for p in def["props"]:
		_prop(p)
	_flush_goods()
	_interior_lights()
	_boundaries()
	covers = _generate_covers()
	return root


## Запекание навмеша. Вызывать ПОСЛЕ добавления уровня в дерево сцены.
func bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Combat.L_WORLD | Combat.L_GLASS
	nm.cell_size = 0.15
	nm.cell_height = 0.1
	nm.agent_radius = 0.3
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.2
	nm.agent_max_slope = 30.0
	nm.filter_baking_aabb = AABB(Vector3(-W / 2.0 - 1.0, -0.5, -D - 1.0), Vector3(W + 2.0, 3.5, D + 5.0))
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)


## Убрать укрытия, до которых нельзя дойти (щели уже радиуса агента).
## Вызывать, когда карта навигации синхронизирована (через кадр после запекания).
func filter_covers(map: RID) -> void:
	var kept := []
	for c in covers:
		var cp: CoverPoint = c
		var near := NavigationServer3D.map_get_closest_point(map, cp.position)
		if Vector2(near.x - cp.position.x, near.z - cp.position.z).length() > 0.25:
			continue
		if cp.kind == "high":
			var pk := NavigationServer3D.map_get_closest_point(map, cp.peek_position())
			if Vector2(pk.x - cp.peek_position().x, pk.z - cp.peek_position().z).length() > 0.3:
				continue
		kept.append(cp)
	covers = kept


func interior_rect() -> Rect2:
	return Rect2(-W / 2.0, -D, W, D)


func door_positions() -> Array:
	var out := []
	for x in def["doors"]:
		out.append(Vector3(float(x), 0, 0))
	return out


# ======================================================================
# Окружение и свет
# ======================================================================

func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var mood: String = def["mood"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sun = DirectionalLight3D.new()
	sun.light_cull_mask = Combat.VIS_EXTERIOR
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	match mood:
		"day":
			var sky := Sky.new()
			var sm := ProceduralSkyMaterial.new()
			sm.sky_top_color = Color("4f86c6")
			sm.sky_horizon_color = Color("b9cde0")
			sm.ground_horizon_color = Color("b9cde0")
			sm.ground_bottom_color = Color("5a5f66")
			sky.sky_material = sm
			env.background_mode = Environment.BG_SKY
			env.sky = sky
			env.ambient_light_color = Color(0.62, 0.66, 0.72)
			env.ambient_light_energy = 0.35
			sun.light_color = Color(1.0, 0.94, 0.84)
			sun.light_energy = 1.25
			sun.rotation_degrees = Vector3(-48, 35, 0)
			env.fog_light_color = Color(0.75, 0.82, 0.9)
			env.fog_density = 0.004
		"night":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color("060912")
			env.ambient_light_color = Color(0.2, 0.24, 0.38)
			env.ambient_light_energy = 0.45
			sun.light_color = Color(0.55, 0.65, 1.0)
			sun.light_energy = 0.22
			sun.rotation_degrees = Vector3(-60, -30, 0)
			env.fog_light_color = Color(0.08, 0.1, 0.18)
			env.fog_density = 0.012
		_:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color("10151d")
			env.ambient_light_color = Color(0.32, 0.36, 0.44)
			env.ambient_light_energy = 0.55
			sun.light_color = Color(0.7, 0.75, 0.85)
			sun.light_energy = 0.35
			sun.rotation_degrees = Vector3(-55, 20, 0)
			env.fog_light_color = Color(0.2, 0.23, 0.3)
			env.fog_density = 0.02
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	we.environment = env
	root.add_child(we)
	root.add_child(sun)
	apply_graphics()


## Применить текущие настройки графики к свету/окружению (вызывается и при смене настроек).
func apply_graphics() -> void:
	env.glow_enabled = Settings.glow_enabled()
	env.fog_enabled = Settings.fog_enabled()
	sun.shadow_enabled = Settings.shadows_enabled()
	for i in interior_lights.size():
		interior_lights[i].shadow_enabled = Settings.omni_shadows_enabled() and i < 2
	if rain:
		rain.emitting = Settings.rain_enabled()
		rain.visible = Settings.rain_enabled()


func _interior_lights() -> void:
	var color: Color = def.get("light_color", Color.WHITE)
	var energy: float = def.get("light_energy", 1.0)
	var flicker: Array = def.get("flicker", [])
	var lamp_mat := Mats.emissive(color, 2.5)
	var idx := 0
	for p in def["lights"]:
		var pos: Vector3 = p
		Mats.add_mesh(root, Mats.box(Vector3(1.2, 0.04, 0.3)), lamp_mat, Vector3(pos.x, WALL_H - 0.04, pos.z),
			Vector3.ZERO, Combat.VIS_INTERIOR, false)
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = energy
		l.omni_range = 6.5
		l.omni_attenuation = 1.1
		l.position = Vector3(pos.x, WALL_H - 0.35, pos.z)
		l.shadow_bias = 0.05
		root.add_child(l)
		interior_lights.append(l)
		if idx in flicker:
			flicker_lights.append(l)
		idx += 1
	apply_graphics()


# ======================================================================
# Пол, стены, фасад, улица
# ======================================================================

func _static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, layer: int = Combat.L_WORLD,
		vis: int = Combat.VIS_INTERIOR, visible_mesh: bool = true, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if visible_mesh and mat:
		Mats.add_mesh(body, Mats.box(size), mat, Vector3.ZERO, Vector3.ZERO, vis)
	parent.add_child(body)
	return body


func _ground() -> void:
	var x0 := -W / 2.0 - 10.0
	var x1 := W / 2.0 + 10.0
	var z0 := -D - 1.0
	var z1 := STREET_Z + 8.0
	# Один большой коллайдер пола.
	_static_box(region, Vector3(x1 - x0, 0.4, z1 - z0), Vector3((x0 + x1) / 2.0, -0.2, (z0 + z1) / 2.0), null,
		Combat.L_WORLD, Combat.VIS_EXTERIOR, false)
	# Визуальный пол зала — плитками 4×4 м: так каждая плитка получает свои ближайшие лампы
	# (у мобильного рендерера лимит источников света на меш).
	var tile_a := Mats.solid(Color("bdb8ae"), 0.35)
	var tile_b := Mats.solid(Color("a9a398"), 0.35)
	var nx := int(ceil(W / 4.0))
	var nz := int(ceil(D / 4.0))
	for ix in nx:
		for iz in nz:
			var tx0 := -W / 2.0 + ix * 4.0
			var tz0 := -D + iz * 4.0
			var tw := minf(4.0, W / 2.0 - tx0)
			var td := minf(4.0, 0.0 - tz0)
			Mats.add_mesh(root, Mats.box(Vector3(tw, 0.02, td)), tile_a if (ix + iz) % 2 == 0 else tile_b,
				Vector3(tx0 + tw / 2.0, -0.01, tz0 + td / 2.0), Vector3.ZERO, Combat.VIS_INTERIOR, false)
	# Тротуар, бордюр, дорога, разметка.
	var walk := Mats.solid(Color("8d8f92") if def["mood"] == "day" else Color("5d6066"), 0.8)
	var asphalt := Mats.solid(Color("2b2d31") if def["mood"] == "day" else Color("18191c"), 0.55 if def["mood"] == "rain" else 0.9)
	Mats.add_mesh(root, Mats.box(Vector3(x1 - x0, 0.02, 3.3)), walk, Vector3(0, -0.01, 1.65), Vector3.ZERO, Combat.VIS_EXTERIOR, false)
	Mats.add_mesh(root, Mats.box(Vector3(x1 - x0, 0.12, 0.2)), Mats.solid(Color("a3a5a8"), 0.8), Vector3(0, 0.05, 3.35), Vector3.ZERO, Combat.VIS_EXTERIOR, false)
	Mats.add_mesh(root, Mats.box(Vector3(x1 - x0, 0.02, z1 - 3.4)), asphalt, Vector3(0, -0.015, 3.4 + (z1 - 3.4) / 2.0), Vector3.ZERO, Combat.VIS_EXTERIOR, false)
	var line := Mats.solid(Color("d8d2b0"), 0.6)
	var x := x0 + 1.0
	while x < x1 - 1.0:
		Mats.add_mesh(root, Mats.box(Vector3(2.0, 0.01, 0.15)), line, Vector3(x, 0.005, 9.5), Vector3.ZERO, Combat.VIS_EXTERIOR, false)
		x += 4.0


func _store_shell() -> void:
	var wall_in := Mats.solid(Color("cfc9bd") if def["mood"] != "night" else Color("a9a59a"), 0.9)
	var facade := Mats.solid(Color("6e3b2e") if def["id"] != "downtown" else Color("3a4250"), 0.85)
	var hw := W / 2.0
	# Проёмы фасада: двери (до пола) и окна.
	var openings := []
	for dx in def["doors"]:
		openings.append([float(dx) - DOOR_W / 2.0, float(dx) + DOOR_W / 2.0, 0.0, DOOR_H])
	for w in def["windows"]:
		openings.append([float(w[0]), float(w[1]), WIN_BOTTOM, WIN_TOP])
	_wall_x(0.1, -hw - WALL_T, hw + WALL_T, FACADE_H, openings, facade, true)
	_wall_x(-D - 0.1, -hw - WALL_T, hw + WALL_T, WALL_H, [], wall_in, false)
	_wall_z(-hw - 0.1, -D, 0.0, WALL_H, wall_in)
	_wall_z(hw + 0.1, -D, 0.0, WALL_H, wall_in)
	# Внутренняя отделка фасада (чтобы изнутри стена была светлой).
	for w in def.get("walls", []):
		var a: Vector2 = w["from"]
		var b: Vector2 = w["to"]
		var size := Vector3(absf(b.x - a.x) + WALL_T, WALL_H, absf(b.y - a.y) + WALL_T)
		var center := Vector3((a.x + b.x) / 2.0, WALL_H / 2.0, (a.y + b.y) / 2.0)
		_static_box(region, size, center, wall_in)
		wall_rects.append({"center": Vector2(center.x, center.z), "half": Vector2(size.x, size.z) / 2.0})
	# Потолок — только визуально.
	# Потолок отбрасывает тень и виден обоим слоям: солнце не «протекает» в зал ни в одном рендерере.
	Mats.add_mesh(root, Mats.box(Vector3(W + 0.4, 0.1, D + 0.4)), Mats.solid(Color("d8d5ce"), 0.9), Vector3(0, WALL_H + 0.05, -D / 2.0),
		Vector3.ZERO, Combat.VIS_INTERIOR | Combat.VIS_EXTERIOR, true)
	# Плинтус и полоса бренда по периметру зала.
	var stripe := Mats.solid(def.get("sign_color", Color.ORANGE).darkened(0.25), 0.6)
	Mats.add_mesh(root, Mats.box(Vector3(W, 0.25, 0.02)), stripe, Vector3(0, 2.6, -D + 0.01), Vector3.ZERO, Combat.VIS_INTERIOR, false)
	# Козырёк и вывеска.
	var sign_c: Color = def.get("sign_color", Color.ORANGE)
	Mats.add_mesh(root, Mats.box(Vector3(W * 0.7, 0.9, 0.25)), Mats.solid(Color("15181d"), 0.6), Vector3(0, 3.55, 0.35), Vector3.ZERO, Combat.VIS_EXTERIOR)
	var lbl := Label3D.new()
	lbl.text = String(def.get("sign", "МАРКЕТ"))
	lbl.font_size = 160
	lbl.pixel_size = 0.0045
	lbl.modulate = sign_c * 1.6
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.position = Vector3(0, 3.55, 0.49)
	lbl.layers = Combat.VIS_EXTERIOR
	root.add_child(lbl)
	var sign_light := OmniLight3D.new()
	sign_light.light_color = sign_c
	sign_light.light_energy = 1.2 if def["mood"] != "day" else 0.3
	sign_light.omni_range = 6.0
	sign_light.position = Vector3(0, 3.2, 1.4)
	root.add_child(sign_light)
	# Козырёк над дверьми.
	for dx in def["doors"]:
		Mats.add_mesh(root, Mats.box(Vector3(2.4, 0.08, 1.2)), Mats.solid(Color("1d2026"), 0.5, 0.4),
			Vector3(float(dx), 2.65, 0.75), Vector3.ZERO, Combat.VIS_EXTERIOR)
		var mat_door := Mats.solid(Color("9aa3ad"), 0.3, 0.8)
		Mats.add_mesh(root, Mats.box(Vector3(0.08, DOOR_H, 0.24)), mat_door, Vector3(float(dx) - DOOR_W / 2.0, DOOR_H / 2.0, 0.1), Vector3.ZERO, Combat.VIS_EXTERIOR)
		Mats.add_mesh(root, Mats.box(Vector3(0.08, DOOR_H, 0.24)), mat_door, Vector3(float(dx) + DOOR_W / 2.0, DOOR_H / 2.0, 0.1), Vector3.ZERO, Combat.VIS_EXTERIOR)


## Стена вдоль X на линии z. openings: [[x0, x1, низ, верх], ...]. Окна получают стекло.
func _wall_x(z: float, x0: float, x1: float, h: float, openings: Array, mat: Material, front: bool) -> void:
	openings.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := x0
	for o in openings:
		var ox0: float = o[0]
		var ox1: float = o[1]
		var bottom: float = o[2]
		var top: float = o[3]
		if ox0 > cursor:
			_static_box(region, Vector3(ox0 - cursor, h, WALL_T), Vector3((cursor + ox0) / 2.0, h / 2.0, z), mat,
				Combat.L_WORLD, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
		if bottom > 0.0:
			_static_box(region, Vector3(ox1 - ox0, bottom, WALL_T), Vector3((ox0 + ox1) / 2.0, bottom / 2.0, z), mat,
				Combat.L_WORLD, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
		if top < h:
			_static_box(region, Vector3(ox1 - ox0, h - top, WALL_T), Vector3((ox0 + ox1) / 2.0, (top + h) / 2.0, z), mat,
				Combat.L_WORLD, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
		if front and bottom > 0.0:
			# Витрина: стекло пропускает пули и взгляд, но не людей (слой glass).
			var gsize := Vector3(ox1 - ox0, top - bottom, 0.04)
			var gpos := Vector3((ox0 + ox1) / 2.0, (top + bottom) / 2.0, z)
			_static_box(region, gsize, gpos, Mats.glass(), Combat.L_GLASS, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
			Mats.add_mesh(root, Mats.box(Vector3(ox1 - ox0, 0.06, 0.3)), Mats.solid(Color("8f969e"), 0.4, 0.6),
				Vector3(gpos.x, bottom, z), Vector3.ZERO, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)
		cursor = maxf(cursor, ox1)
	if cursor < x1:
		_static_box(region, Vector3(x1 - cursor, h, WALL_T), Vector3((cursor + x1) / 2.0, h / 2.0, z), mat,
			Combat.L_WORLD, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)


func _wall_z(x: float, z0: float, z1: float, h: float, mat: Material) -> void:
	_static_box(region, Vector3(WALL_T, h, z1 - z0), Vector3(x, h / 2.0, (z0 + z1) / 2.0), mat,
		Combat.L_WORLD, Combat.VIS_EXTERIOR | Combat.VIS_INTERIOR)


func _exterior() -> void:
	var mood: String = def["mood"]
	var hw := W / 2.0
	# Соседние здания по бокам и напротив (фон для роликов).
	var palette := [Color("5b4a42"), Color("47505c"), Color("6b5d4f"), Color("3e4652")]
	for side in [-1, 1]:
		var bw := 9.0
		var cx: float = side * (hw + WALL_T + bw / 2.0)
		var h := rng.randf_range(6.5, 10.0)
		_static_box(region, Vector3(bw, h, D + 0.4), Vector3(cx, h / 2.0, -D / 2.0), Mats.solid(palette[(side + 1) / 2], 0.9),
			Combat.L_WORLD, Combat.VIS_EXTERIOR)
		_facade_windows(Vector3(cx, 0, 0.21), bw, h, mood)
	for i in 5:
		var bw2 := rng.randf_range(7.0, 11.0)
		var h2 := rng.randf_range(8.0, 16.0)
		var cx2 := -24.0 + i * 12.0
		Mats.add_mesh(root, Mats.box(Vector3(bw2, h2, 6.0)), Mats.solid(palette[i % palette.size()], 0.9),
			Vector3(cx2, h2 / 2.0, STREET_Z + 7.0), Vector3.ZERO, Combat.VIS_EXTERIOR)
		_facade_windows(Vector3(cx2, 0, STREET_Z + 3.98), bw2, h2, mood, true)
	# Фонари.
	for sx in [-hw - 2.0, hw + 2.0]:
		var pole := Mats.solid(Color("2b2f35"), 0.5, 0.6)
		Mats.add_mesh(root, Mats.cylinder(0.07, 5.0, 8), pole, Vector3(sx, 2.5, 3.0), Vector3.ZERO, Combat.VIS_EXTERIOR)
		Mats.add_mesh(root, Mats.box(Vector3(0.5, 0.12, 0.25)), Mats.emissive(Color(1.0, 0.75, 0.45), 3.0 if mood != "day" else 0.3),
			Vector3(sx, 5.0, 3.0), Vector3.ZERO, Combat.VIS_EXTERIOR, false)
		if mood != "day":
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.72, 0.42)
			lamp.light_energy = 2.0
			lamp.omni_range = 11.0
			lamp.light_cull_mask = Combat.VIS_EXTERIOR
			lamp.position = Vector3(sx, 4.7, 3.0)
			root.add_child(lamp)
	if mood == "rain":
		_rain()


func _facade_windows(base: Vector3, width: float, height: float, mood: String, facing_back: bool = false) -> void:
	var lit := Mats.emissive(Color(1.0, 0.85, 0.55), 1.4)
	var dark := Mats.solid(Color("1a2230"), 0.1, 0.4)
	var cols := int(width / 2.2)
	var floors := int((height - 4.0) / 3.0)
	for f in floors:
		for c in cols:
			var on := mood != "day" and rng.randf() < 0.45
			var px := base.x - width / 2.0 + 1.1 + c * 2.2
			var py := 4.8 + f * 3.0
			Mats.add_mesh(root, Mats.box(Vector3(1.1, 1.4, 0.05)), lit if on else dark,
				Vector3(px, py, base.z + (-0.02 if facing_back else 0.0)), Vector3.ZERO, Combat.VIS_EXTERIOR, false)


func _rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 900
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-W, -2, -2), Vector3(W * 2.0, 14, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(W / 2.0 + 8.0, 0.5, 7.0)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.35, 0.012)
	drop.material = Mats.unshaded(Color(0.75, 0.8, 0.9, 0.35))
	rain.draw_pass_1 = drop
	rain.position = Vector3(0, 10.0, 7.0)
	rain.layers = Combat.VIS_EXTERIOR
	root.add_child(rain)


## Невидимые стены по краям улицы — чтобы игрок не ушёл с карты.
func _boundaries() -> void:
	var hw := W / 2.0 + 9.0
	_static_box(region, Vector3(0.5, 4, STREET_Z + 2), Vector3(-hw, 2, STREET_Z / 2.0), null, Combat.L_WORLD, 0, false)
	_static_box(region, Vector3(0.5, 4, STREET_Z + 2), Vector3(hw, 2, STREET_Z / 2.0), null, Combat.L_WORLD, 0, false)
	_static_box(region, Vector3(hw * 2.0, 4, 0.5), Vector3(0, 2, STREET_Z - 1.0), null, Combat.L_WORLD, 0, false)


# ======================================================================
# Реквизит
# ======================================================================

func _prop(p: Dictionary) -> void:
	var kind: String = p["kind"]
	if not PROPS.has(kind):
		push_warning("LevelBuilder: неизвестный реквизит '%s'" % kind)
		return
	var info: Dictionary = PROPS[kind]
	var size: Vector3 = info["size"]
	var pos: Vector3 = p["pos"]
	var rot := int(p.get("rot", 0)) % 360
	var node := Node3D.new()
	node.name = kind
	node.position = pos
	node.rotation.y = deg_to_rad(rot)
	region.add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = Combat.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, size.y / 2.0, 0)
	body.add_child(cs)
	node.add_child(body)
	var imported := _load_prop_glb(kind)
	if imported:
		node.add_child(imported)
	else:
		_prop_visuals(kind, node, size)
	var swap := rot == 90 or rot == 270
	var half := Vector2(size.z, size.x) / 2.0 if swap else Vector2(size.x, size.z) / 2.0
	prop_rects.append({"center": Vector2(pos.x, pos.z), "half": half, "cover": info["cover"]})


## Модель реквизита из Blender-пайплайна (res://assets/models/props/<kind>.glb), если есть.
## Коллизия и укрытия всегда строятся по размерам из PROPS — ассет на геймплей не влияет.
func _load_prop_glb(kind: String) -> Node3D:
	var path := "res://assets/models/props/%s.glb" % kind
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	if inst:
		_set_layers(inst, Combat.VIS_INTERIOR)
	return inst


func _set_layers(n: Node, layers: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layers
	for c in n.get_children():
		_set_layers(c, layers)


func _prop_visuals(kind: String, node: Node3D, size: Vector3) -> void:
	match kind:
		"shelf": _shelf(node, size)
		"shelf_wall": _shelf_wall(node, size)
		"fridge": _fridge(node, size)
		"counter": _counter(node, size)
		"crates": _crates(node)
		"pallet": _pallet(node, size)
		"freezer": _freezer(node, size)
		"pillar": _pillar(node, size)
		"atm": _atm(node, size)
		"display": _display(node, size)


func _m(node: Node3D, size: Vector3, pos: Vector3, c: Color, rough: float = 0.8, metal: float = 0.0) -> void:
	Mats.add_mesh(node, Mats.box(size), Mats.solid(c, rough, metal), pos, Vector3.ZERO, Combat.VIS_INTERIOR)


func _goods_row(node: Node3D, x0: float, x1: float, y: float, z: float, depth: float, max_h: float) -> void:
	var x := x0
	var base := rng.randi() % GOODS_COLORS.size()
	while x < x1 - 0.1:
		var w := rng.randf_range(0.09, 0.2)
		var h := rng.randf_range(0.1, max_h)
		if x + w > x1:
			break
		if rng.randf() > 0.12:  # пустые места на полках — магазин грабят
			var local := Transform3D(Basis().scaled(Vector3(w * 0.92, h, depth)), Vector3(x + w / 2.0, y + h / 2.0, z))
			_goods_xf.append(node.transform * local)
			var c: Color = GOODS_COLORS[(base + int(x * 7.0)) % GOODS_COLORS.size()]
			_goods_col.append(c.lightened(rng.randf_range(-0.15, 0.15)))
		x += w


func _flush_goods() -> void:
	if _goods_xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Mats.box(Vector3.ONE)
	mm.instance_count = _goods_xf.size()
	for i in _goods_xf.size():
		mm.set_instance_transform(i, _goods_xf[i])
		mm.set_instance_color(i, _goods_col[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Goods"
	mmi.multimesh = mm
	mmi.material_override = Mats.vertex_colored()
	mmi.layers = Combat.VIS_INTERIOR
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func _shelf(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, 0.1, s.z), Vector3(0, 0.05, 0), Color("3a3d42"))
	_m(n, Vector3(s.x, s.y - 0.1, 0.05), Vector3(0, s.y / 2.0 + 0.05, 0), Color("b9bec4"), 0.5, 0.4)
	for ex in [-s.x / 2.0 + 0.02, s.x / 2.0 - 0.02]:
		_m(n, Vector3(0.04, s.y, s.z), Vector3(ex, s.y / 2.0, 0), Color("8c939b"), 0.5, 0.4)
	for side in [-1, 1]:
		for y in [0.38, 0.78, 1.16]:
			_m(n, Vector3(s.x - 0.08, 0.025, 0.36), Vector3(0, y, 0.2 * side), Color("d4d7db"), 0.5, 0.3)
			_goods_row(n, -s.x / 2.0 + 0.06, s.x / 2.0 - 0.06, y + 0.013, 0.2 * side, 0.26, 0.24 if y < 1.0 else 0.17)
		_goods_row(n, -s.x / 2.0 + 0.06, s.x / 2.0 - 0.06, 0.1, 0.2 * side, 0.3, 0.26)


func _shelf_wall(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, s.y, 0.04), Vector3(0, s.y / 2.0, -s.z / 2.0 + 0.02), Color("9aa1a8"), 0.5, 0.4)
	for y in [0.1, 0.5, 0.92, 1.34, 1.74]:
		_m(n, Vector3(s.x - 0.04, 0.025, s.z - 0.06), Vector3(0, y, 0.02), Color("d4d7db"), 0.5, 0.3)
		_goods_row(n, -s.x / 2.0 + 0.05, s.x / 2.0 - 0.05, y + 0.013, 0.02, 0.32, 0.3)


func _fridge(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, s.y, s.z - 0.04), Vector3(0, s.y / 2.0, -0.02), Color("e9ecef"), 0.4, 0.2)
	Mats.add_mesh(n, Mats.box(Vector3(s.x - 0.12, s.y - 0.32, 0.02)), Mats.emissive(Color(0.72, 0.88, 1.0), 0.9),
		Vector3(0, s.y / 2.0 - 0.06, s.z / 2.0 - 0.01), Vector3.ZERO, Combat.VIS_INTERIOR, false)
	for y in [0.55, 1.0, 1.45]:
		_m(n, Vector3(s.x - 0.12, 0.03, 0.03), Vector3(0, y, s.z / 2.0 + 0.005), Color("5d6670"), 0.5, 0.5)
	_m(n, Vector3(0.04, s.y - 0.3, 0.03), Vector3(0, s.y / 2.0 - 0.06, s.z / 2.0 + 0.005), Color("5d6670"), 0.5, 0.5)
	Mats.add_mesh(n, Mats.box(Vector3(s.x, 0.16, 0.04)), Mats.emissive(def.get("sign_color", Color.ORANGE), 1.2),
		Vector3(0, s.y - 0.1, s.z / 2.0), Vector3.ZERO, Combat.VIS_INTERIOR, false)


func _counter(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, s.y - 0.05, s.z), Vector3(0, (s.y - 0.05) / 2.0, 0), Color("4a3f37"), 0.7)
	_m(n, Vector3(s.x + 0.1, 0.05, s.z + 0.06), Vector3(0, s.y - 0.025, 0), Color("d9d4cc"), 0.3)
	_m(n, Vector3(s.x * 0.9, 0.18, 0.02), Vector3(0, 0.6, -s.z / 2.0 - 0.01), def.get("sign_color", Color.ORANGE), 0.5)
	# Касса: корпус, экран, денежный ящик, терминал.
	var reg := Node3D.new()
	reg.position = Vector3(0.6, s.y, 0.05)
	n.add_child(reg)
	_m(reg, Vector3(0.42, 0.12, 0.38), Vector3(0, 0.06, 0), Color("2a2c30"), 0.5, 0.3)
	_m(reg, Vector3(0.4, 0.06, 0.32), Vector3(0, 0.15, 0.02), Color("3a3d42"), 0.5, 0.3)
	Mats.add_mesh(reg, Mats.box(Vector3(0.3, 0.2, 0.025)), Mats.emissive(Color(0.3, 1.0, 0.55), 1.2),
		Vector3(0, 0.32, -0.1), Vector3(deg_to_rad(-20), 0, 0), Combat.VIS_INTERIOR, false)
	_m(reg, Vector3(0.1, 0.05, 0.16), Vector3(-0.3, 0.025, 0.05), Color("15161a"), 0.5)
	_m(n, Vector3(0.5, 0.35, 0.25), Vector3(-0.8, s.y + 0.175, 0.2), Color("7f8c8d"), 0.6, 0.3)
	_goods_row(n, -1.03, -0.57, s.y + 0.06, 0.2, 0.2, 0.12)


func _crates(n: Node3D) -> void:
	var c := Color("a9824f")
	_m(n, Vector3(1.0, 0.55, 1.0), Vector3(0, 0.275, 0), c, 0.95)
	var top := Node3D.new()
	top.position = Vector3(0.05, 0.55, -0.02)
	top.rotation.y = deg_to_rad(rng.randf_range(-15.0, 15.0))
	n.add_child(top)
	_m(top, Vector3(0.8, 0.5, 0.8), Vector3(0, 0.25, 0), c.darkened(0.1), 0.95)
	_m(top, Vector3(0.82, 0.04, 0.12), Vector3(0, 0.5, 0), Color("c9b28a"), 0.9)


func _pallet(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, 0.14, s.z), Vector3(0, 0.07, 0), Color("8a6a43"), 0.95)
	_m(n, Vector3(s.x - 0.1, s.y - 0.16, s.z - 0.06), Vector3(0, 0.14 + (s.y - 0.16) / 2.0, 0), Color("b8c2c9"), 0.25, 0.1)


func _freezer(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, s.y - 0.05, s.z), Vector3(0, (s.y - 0.05) / 2.0, 0), Color("f1f3f5"), 0.35, 0.2)
	Mats.add_mesh(n, Mats.box(Vector3(s.x - 0.1, 0.03, s.z - 0.1)), Mats.emissive(Color(0.6, 0.85, 1.0), 0.8),
		Vector3(0, s.y - 0.03, 0), Vector3.ZERO, Combat.VIS_INTERIOR, false)
	_m(n, Vector3(s.x, 0.12, s.z + 0.02), Vector3(0, 0.06, 0), Color("4a5058"), 0.6)


func _pillar(n: Node3D, s: Vector3) -> void:
	_m(n, s, Vector3(0, s.y / 2.0, 0), Color("a8a49c"), 0.95)
	_m(n, Vector3(s.x + 0.04, 0.2, s.z + 0.04), Vector3(0, 0.1, 0), Color("4a4d52"), 0.7)
	_m(n, Vector3(s.x + 0.02, 0.3, s.z + 0.02), Vector3(0, 2.0, 0), def.get("sign_color", Color.ORANGE).darkened(0.3), 0.6)


func _atm(n: Node3D, s: Vector3) -> void:
	_m(n, s, Vector3(0, s.y / 2.0, 0), Color("1f3b6e"), 0.5, 0.3)
	Mats.add_mesh(n, Mats.box(Vector3(0.36, 0.28, 0.02)), Mats.emissive(Color(0.45, 0.8, 1.0), 1.5),
		Vector3(0, 1.25, s.z / 2.0 + 0.01), Vector3.ZERO, Combat.VIS_INTERIOR, false)
	_m(n, Vector3(0.45, 0.12, 0.12), Vector3(0, 0.95, s.z / 2.0 + 0.05), Color("2b2d31"), 0.5, 0.4)


func _display(n: Node3D, s: Vector3) -> void:
	_m(n, Vector3(s.x, s.y, s.z), Vector3(0, s.y / 2.0, 0), Color("c0392b"), 0.6)
	for y in [0.45, 0.85]:
		_goods_row(n, -s.x / 2.0 + 0.05, s.x / 2.0 - 0.05, y, s.z / 2.0 + 0.08, 0.15, 0.2)
	_m(n, Vector3(s.x, 0.25, 0.04), Vector3(0, s.y + 0.15, 0), Color("f1c40f"), 0.5)


# ======================================================================
# Автогенерация укрытий
# ======================================================================

func _generate_covers() -> Array:
	var out := []
	for r in prop_rects:
		var kind: String = r["cover"]
		if kind == "":
			continue
		var c: Vector2 = r["center"]
		var h: Vector2 = r["half"]
		# 4 стороны: (нормаль наружу, касательная, полуглубина по нормали, полудлина по касательной).
		var sides := [
			[Vector2(1, 0), Vector2(0, 1), h.x, h.y],
			[Vector2(-1, 0), Vector2(0, 1), h.x, h.y],
			[Vector2(0, 1), Vector2(1, 0), h.y, h.x],
			[Vector2(0, -1), Vector2(1, 0), h.y, h.x],
		]
		for sd in sides:
			var n: Vector2 = sd[0]
			var t: Vector2 = sd[1]
			var hn: float = sd[2]
			var ht: float = sd[3]
			if kind == "low":
				var count := maxi(1, int(ht * 2.0 / 1.1))
				for i in count:
					var off := -ht + ht * 2.0 * (i + 0.5) / count
					var p := c + n * (hn + COVER_OFFSET) + t * off
					if _point_free(p):
						out.append(CoverPoint.new(Vector3(p.x, 0, p.y), Vector3(-n.x, 0, -n.y), "low"))
			else:
				var p2 := c + n * (hn + COVER_OFFSET)
				if not _point_free(p2):
					continue
				var step := ht + 0.55
				for sgn in [1.0, -1.0]:
					var peek: Vector2 = t * step * sgn
					if _point_free(p2 + peek):
						out.append(CoverPoint.new(Vector3(p2.x, 0, p2.y), Vector3(-n.x, 0, -n.y), "high", Vector3(peek.x, 0, peek.y)))
						break
	return out


func _point_free(p: Vector2) -> bool:
	var m := 0.38
	if p.x < -W / 2.0 + m or p.x > W / 2.0 - m or p.y < -D + m or p.y > -m:
		return false
	for r in prop_rects:
		var c: Vector2 = r["center"]
		var h: Vector2 = r["half"]
		if absf(p.x - c.x) < h.x + 0.33 and absf(p.y - c.y) < h.y + 0.33:
			return false
	for w in wall_rects:
		var c2: Vector2 = w["center"]
		var h2: Vector2 = w["half"]
		if absf(p.x - c2.x) < h2.x + 0.35 and absf(p.y - c2.y) < h2.y + 0.35:
			return false
	return true
