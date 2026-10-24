"""
Утилиты Blender для генератора ассетов (Blender 4.x, bpy).

Ключевое: перевод координат Godot → Blender.
  Godot: Y вверх, вперёд -Z.  Blender: Z вверх, вперёд -Y (так ждёт экспортёр glTF с +Y up).
  Точка:    (x, y, z)_godot -> (x, -z, y)_blender
  Размер:   (sx, sy, sz)    -> (sx, sz, sy)
  Эйлер Godot (порядок YXZ: сначала Z, потом X, потом Y) -> Blender
            rotation_mode 'YXZ', значения (rx, -rz, ry).
  (поворот вокруг оси Godot Z соответствует повороту вокруг Blender -Y)
Экспортёр glTF (export_yup=True) выполняет обратное преобразование — в Godot
узлы приходят ровно с теми осями и углами, что у процедурных моделей.
"""

import bpy


def g2b(v):
    x, y, z = v
    return (x, -z, y)


def size_g2b(s):
    return (s[0], s[2], s[1])


def euler_g2b(e):
    rx, ry, rz = e
    return (rx, -rz, ry)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    return scene


_MATS = {}


def material(hex_color, emission=0.0, roughness=0.8, metallic=0.0):
    key = (hex_color, emission, roughness, metallic)
    if key in _MATS and _MATS[key].name in bpy.data.materials:
        return _MATS[key]
    r, g, b = (int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    # sRGB -> linear: Blender хранит base color линейным.
    lin = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in (r, g, b))
    mat = bpy.data.materials.new("M_" + hex_color + ("_E" if emission else ""))
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    _MATS[key] = mat
    return mat


def empty(name, parent=None, pos=(0, 0, 0)):
    """Пустой узел-шарнир (в glTF становится узлом, в Godot — Node3D)."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    obj.location = g2b(pos)
    obj.rotation_mode = "YXZ"
    return obj


def box(name, size, pos, mat, parent=None):
    """Low-poly коробка (12 треугольников) с размером в координатах Godot."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = size_g2b(size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if parent is not None:
        obj.parent = parent
    obj.location = g2b(pos)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, radius, depth, pos, mat, parent=None, vertices=10, axis="y"):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    obj = bpy.context.active_object
    obj.name = name
    if axis == "x":
        obj.rotation_euler = (0.0, 1.5707963, 0.0)
    elif axis == "y":
        obj.rotation_euler = (0.0, 0.0, 0.0)  # Blender Z = Godot Y
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if parent is not None:
        obj.parent = parent
    obj.location = g2b(pos)
    obj.data.materials.append(mat)
    return obj


def key_rotation(obj, frame, euler_godot):
    obj.rotation_euler = euler_g2b(euler_godot)
    obj.keyframe_insert(data_path="rotation_euler", frame=frame)


def key_height(obj, frame, y_godot):
    loc = obj.location
    obj.location = (loc[0], loc[1], y_godot)
    obj.keyframe_insert(data_path="location", index=2, frame=frame)


def set_height(obj, y_godot):
    loc = obj.location
    obj.location = (loc[0], loc[1], y_godot)


def push_action_to_nla(obj, action, track_name):
    """Клип = NLA-трек с одинаковым именем на всех узлах; экспортёр glTF
    в режиме NLA_TRACKS объединяет такие треки в одну анимацию."""
    if obj.animation_data is None:
        obj.animation_data_create()
    track = obj.animation_data.nla_tracks.new()
    track.name = track_name
    start = int(action.frame_range[0])
    track.strips.new(track_name, start, action)
    obj.animation_data.action = None


def set_linear_or_loop(action, cyclic):
    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER" if cyclic else "LINEAR"
        if cyclic:
            fc.modifiers.new(type="CYCLES")


def export_glb(path, selected_only=False):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_optimize_animation_size=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        use_selection=selected_only,
    )


def triangle_count():
    n = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            n += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    return n
