class_name Mats
extends RefCounted
## Кэш материалов и примитивных мешей.
## Один ресурс на цвет/размер: меньше памяти и смен состояний рендера на iOS.

static var _mat: Dictionary = {}
static var _mesh: Dictionary = {}


static func solid(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "solid|%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mat[key] = m
	return _mat[key]


static func emissive(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "emit|%s|%.2f" % [c.to_html(), energy]
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		m.roughness = 0.4
		_mat[key] = m
	return _mat[key]


static func glass(tint: Color = Color(0.55, 0.72, 0.82, 0.16)) -> StandardMaterial3D:
	var key := "glass|%s" % tint.to_html()
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = tint
		m.roughness = 0.05
		m.metallic = 0.3
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat[key] = m
	return _mat[key]


static func unshaded(c: Color, additive: bool = false) -> StandardMaterial3D:
	var key := "unsh|%s|%s" % [c.to_html(), additive]
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat[key] = m
	return _mat[key]


## Уникальный (не кэшируемый) материал — для того, что анимируется по отдельности.
static func unique_unshaded(c: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func vertex_colored() -> StandardMaterial3D:
	if not _mat.has("vcolor"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.7
		_mat["vcolor"] = m
	return _mat["vcolor"]


static func box(size: Vector3) -> BoxMesh:
	var key := "box|%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	if not _mesh.has(key):
		var b := BoxMesh.new()
		b.size = size
		_mesh[key] = b
	return _mesh[key]


static func cylinder(radius: float, height: float, segments: int = 10) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%d" % [radius, height, segments]
	if not _mesh.has(key):
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = height
		c.radial_segments = segments
		c.rings = 1
		_mesh[key] = c
	return _mesh[key]


static func sphere(radius: float) -> SphereMesh:
	var key := "sph|%.3f" % radius
	if not _mesh.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = 10
		s.rings = 6
		_mesh[key] = s
	return _mesh[key]


## Быстро добавить меш-примитив в узел.
static func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, layers: int = 1, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
