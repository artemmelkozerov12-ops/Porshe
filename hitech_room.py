"""
Hi-tech living room — процедурная сцена для Blender 4.x (Cycles).

Запуск:
  GUI:   Blender -> вкладка Scripting -> Open -> hitech_room.py -> Run Script -> F12
  CLI:   blender -b -P hitech_room.py      (рендер в hitech_room.png + hitech_room.blend в текущей папке)

Планировка повторяет референс: два окна на задней стене, ТВ-зона слева,
диван справа, круглый столик по центру, пуф, растения, кот на подоконнике.
"""
import bpy
import math
import os
import random
from mathutils import Vector

random.seed(7)

# ---------------------------------------------------------------- очистка сцены
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
    for block in list(coll):
        if block.users == 0:
            coll.remove(block)

scene = bpy.context.scene

# ---------------------------------------------------------------- размеры комнаты
W = 2.1      # половина ширины (x от -W до W)
D = 5.0      # глубина до внутренней грани задней стены
H = 2.8      # высота потолка
T = 0.15     # толщина стен
SILL = 0.86  # низ окна / верх подоконника
WIN_TOP = 2.5
WINDOWS = [(-1.7, -0.4), (0.4, 1.7)]


# ---------------------------------------------------------------- материалы
def _set(node, names, value):
    for n in ([names] if isinstance(names, str) else names):
        if n in node.inputs:
            node.inputs[n].default_value = value
            return


def material(name, color, rough=0.5, metal=0.0, transmission=0.0, coat=0.0,
             emission=None, strength=0.0, ior=1.45, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    _set(b, "Base Color", (*color, 1.0))
    _set(b, "Roughness", rough)
    _set(b, "Metallic", metal)
    _set(b, ["Transmission Weight", "Transmission"], transmission)
    _set(b, ["Coat Weight", "Clearcoat"], coat)
    _set(b, ["Sheen Weight", "Sheen"], sheen)
    _set(b, "IOR", ior)
    if emission:
        _set(b, ["Emission Color", "Emission"], (*emission, 1.0))
        _set(b, "Emission Strength", strength)
    return m


def add_noise_bump(m, scale, strength, color_a=None, color_b=None):
    """Лёгкая неоднородность поверхности: шум -> bump (+ вариация цвета)."""
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 8.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    if color_a and color_b:
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (*color_a, 1.0)
        ramp.color_ramp.elements[1].color = (*color_b, 1.0)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])


M = {
    "concrete": material("PolishedConcrete", (0.42, 0.42, 0.41), rough=0.22, coat=0.3),
    "wall": material("WhiteWall", (0.85, 0.85, 0.84), rough=0.65),
    "graphite": material("GraphiteMicrocement", (0.055, 0.057, 0.06), rough=0.55),
    "ceiling": material("Ceiling", (0.9, 0.9, 0.9), rough=0.8),
    "alu_black": material("BlackAluminium", (0.02, 0.02, 0.022), rough=0.3, metal=1.0),
    "chrome": material("Chrome", (0.9, 0.9, 0.92), rough=0.05, metal=1.0),
    "glass": material("Glass", (1.0, 1.0, 1.0), rough=0.0, transmission=1.0, ior=1.5),
    "glass_table": material("TableGlass", (0.75, 0.85, 0.82), rough=0.02, transmission=1.0, ior=1.5),
    "lacquer": material("WhiteLacquer", (0.82, 0.82, 0.82), rough=0.15, coat=1.0),
    "screen": material("TVScreen", (0.005, 0.005, 0.006), rough=0.05, coat=1.0),
    "quartz": material("WhiteQuartz", (0.8, 0.8, 0.78), rough=0.12, coat=0.6),
    "fabric": material("AnthraciteFabric", (0.07, 0.072, 0.075), rough=0.9, sheen=0.6),
    "pillow_w": material("PillowWhite", (0.7, 0.7, 0.68), rough=0.9, sheen=0.6),
    "pillow_g": material("PillowSage", (0.24, 0.32, 0.25), rough=0.9, sheen=0.6),
    "leather": material("BlackLeather", (0.02, 0.02, 0.02), rough=0.35, coat=0.3),
    "rug": material("Rug", (0.5, 0.5, 0.48), rough=1.0, sheen=0.8),
    "pot": material("PotMatteWhite", (0.78, 0.78, 0.76), rough=0.55),
    "soil": material("Soil", (0.03, 0.02, 0.015), rough=1.0),
    "stem": material("Stem", (0.08, 0.16, 0.05), rough=0.6),
    "leaf": material("Leaf", (0.04, 0.16, 0.05), rough=0.35, sheen=0.2),
    "cat": material("CatFur", (0.12, 0.12, 0.13), rough=0.85, sheen=1.0),
    "art": material("ArtCanvas", (0.36, 0.45, 0.37), rough=0.9),
    "ground": material("Ground", (0.18, 0.22, 0.15), rough=0.9),
    "led_warm": material("LED_Warm", (1, 1, 1), emission=(1.0, 0.86, 0.7), strength=30),
    "led_neutral": material("LED_Neutral", (1, 1, 1), emission=(1.0, 0.94, 0.86), strength=40),
    "led_cool": material("LED_Cool", (1, 1, 1), emission=(0.65, 0.8, 1.0), strength=12),
}
add_noise_bump(M["concrete"], 6.0, 0.03, (0.36, 0.36, 0.35), (0.5, 0.5, 0.49))
add_noise_bump(M["graphite"], 25.0, 0.05, (0.045, 0.047, 0.05), (0.075, 0.077, 0.08))
add_noise_bump(M["fabric"], 400.0, 0.08)
add_noise_bump(M["rug"], 600.0, 0.25)
add_noise_bump(M["wall"], 40.0, 0.01)


# ---------------------------------------------------------------- примитивы
def _smooth(o, angle=35):
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))  # Blender 4.1+
    except Exception:
        bpy.ops.object.shade_smooth()
        if hasattr(o.data, "use_auto_smooth"):
            o.data.use_auto_smooth = True
            o.data.auto_smooth_angle = math.radians(angle)


def box(name, x0, x1, y0, y1, z0, z1, mat, bevel=0.0, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    o = bpy.context.active_object
    o.name = name
    o.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    if bevel:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        _smooth(o)
    return o


def cyl(name, loc, r, depth, mat, verts=64):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    _smooth(o)
    return o


def rod(name, p0, p1, r, mat, verts=8):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(p0 + p1) / 2, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
    o.data.materials.append(mat)
    _smooth(o)
    return o


def ellipsoid(name, loc, scale, mat, rot_dir=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=loc, segments=24, ring_count=12)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    if rot_dir is not None:
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((1, 0, 0)).rotation_difference(Vector(rot_dir))
    o.data.materials.append(mat)
    _smooth(o, 80)
    return o


# ---------------------------------------------------------------- коробка комнаты
box("Floor", -W - T, W + T, -0.6, D + T, -0.1, 0, M["concrete"])
box("Ceiling", -W - T, W + T, -0.6, D + T, H, H + 0.1, M["ceiling"])
box("WallLeft", -W - T, -W, -0.6, D + T, 0, H, M["wall"])
box("WallRight", W, W + T, -0.6, D + T, 0, H, M["wall"])

# задняя стена собрана из кусков вокруг двух оконных проёмов
box("BackWall_Bottom", -W, W, D, D + T, 0, SILL, M["wall"])
box("BackWall_Top", -W, W, D, D + T, WIN_TOP, H, M["wall"])
xs = [-W] + [v for w in WINDOWS for v in w] + [W]
for i in range(0, len(xs), 2):
    box(f"BackWall_Pier{i}", xs[i], xs[i + 1], D, D + T, SILL, WIN_TOP, M["wall"])

# окна: чёрный алюминий, импост, стекло без теней (иначе Cycles затемнит интерьер)
fy0, fy1 = D + 0.04, D + 0.11
for n, (a, b) in enumerate(WINDOWS):
    f = 0.05
    box(f"Frame{n}_L", a, a + f, fy0, fy1, SILL, WIN_TOP, M["alu_black"])
    box(f"Frame{n}_R", b - f, b, fy0, fy1, SILL, WIN_TOP, M["alu_black"])
    box(f"Frame{n}_T", a, b, fy0, fy1, WIN_TOP - f, WIN_TOP, M["alu_black"])
    box(f"Frame{n}_B", a, b, fy0, fy1, SILL, SILL + f, M["alu_black"])
    c = (a + b) / 2
    box(f"Frame{n}_Mullion", c - 0.02, c + 0.02, fy0, fy1, SILL, WIN_TOP, M["alu_black"])
    g = box(f"Glass{n}", a, b, D + 0.07, D + 0.078, SILL, WIN_TOP, M["glass"])
    g.visible_shadow = False

# сплошной подоконник-полка из кварца + LED-подсветка снизу
box("Ledge", -W, W, D - 0.28, D + 0.04, SILL - 0.04, SILL, M["quartz"], bevel=0.004)
box("Ledge_LED", -W + 0.05, W - 0.05, D - 0.06, D - 0.03, SILL - 0.05, SILL - 0.04, M["led_warm"])

# картина между окнами (кивок на зелёные постеры с референса)
box("Art_Frame", -0.28, 0.28, D - 0.03, D, 1.35, 2.15, M["alu_black"])
box("Art_Canvas", -0.25, 0.25, D - 0.035, D - 0.03, 1.38, 2.12, M["art"])

# улица: земля под окнами
bpy.ops.mesh.primitive_plane_add(size=300, location=(0, 50, -3))
bpy.context.active_object.data.materials.append(M["ground"])

# ---------------------------------------------------------------- ТВ-зона (левая стена)
box("AccentPanel", -W, -W + 0.02, 1.5, 4.1, 0, H, M["graphite"])
box("TV_Backlight", -W + 0.02, -W + 0.025, 1.98, 3.62, 0.9, 1.82, M["led_cool"])
box("TV_Body", -W + 0.03, -W + 0.06, 2.08, 3.52, 0.95, 1.76, M["alu_black"], bevel=0.005)
box("TV_Screen", -W + 0.06, -W + 0.064, 2.1, 3.5, 0.97, 1.74, M["screen"])

box("Console", -W + 0.02, -W + 0.44, 1.85, 3.75, 0.28, 0.62, M["lacquer"], bevel=0.006)
for y in (2.48, 3.12):
    box(f"Console_Groove{y}", -W + 0.44, -W + 0.443, y - 0.002, y + 0.002, 0.3, 0.6, M["alu_black"])
box("Console_LED", -W + 0.08, -W + 0.36, 1.95, 3.65, 0.265, 0.28, M["led_warm"])
cyl("Console_Vase", (-W + 0.22, 3.5, 0.75), 0.06, 0.26, M["alu_black"])

# ---------------------------------------------------------------- диван (правая стена)
sx0, sx1, sy0, sy1 = W - 0.95, W - 0.02, 1.6, 4.3
box("Sofa_Base", sx0, sx1, sy0, sy1, 0.1, 0.38, M["fabric"], bevel=0.03, segments=5)
box("Sofa_Back", sx1 - 0.22, sx1, sy0 + 0.2, sy1 - 0.2, 0.38, 0.85, M["fabric"], bevel=0.05, segments=6)
for i, (y0, y1) in enumerate([(sy0 + 0.2, (sy0 + sy1) / 2), ((sy0 + sy1) / 2, sy1 - 0.2)]):
    box(f"Sofa_Seat{i}", sx0 + 0.02, sx1 - 0.22, y0 + 0.005, y1 - 0.005, 0.38, 0.52, M["fabric"], bevel=0.05, segments=6)
for i, (y0, y1) in enumerate([(sy0, sy0 + 0.2), (sy1 - 0.2, sy1)]):
    box(f"Sofa_Arm{i}", sx0, sx1, y0, y1, 0.1, 0.64, M["fabric"], bevel=0.04, segments=6)
for i, y in enumerate((sy0 + 0.1, sy1 - 0.1)):
    box(f"Sofa_Sled{i}", sx0 + 0.05, sx1 - 0.05, y - 0.012, y + 0.012, 0.0, 0.1, M["chrome"], bevel=0.004)

pw = box("Pillow_White", 0, 0.14, -0.24, 0.24, -0.22, 0.22, M["pillow_w"], bevel=0.06, segments=6)
pw.location = (sx1 - 0.32, sy1 - 0.55, 0.72)
pw.rotation_euler = (0, math.radians(-14), math.radians(8))
pg = box("Pillow_Sage", 0, 0.14, -0.22, 0.22, -0.2, 0.2, M["pillow_g"], bevel=0.06, segments=6)
pg.location = (sx1 - 0.34, sy1 - 0.95, 0.7)
pg.rotation_euler = (0, math.radians(-12), math.radians(-6))

box("Sofa_WallLED", W - 0.02, W, 1.7, 4.2, 1.95, 1.97, M["led_neutral"])

# ---------------------------------------------------------------- столик, пуф, ковёр
tx, ty = -0.25, 2.55
box("Rug", -1.45, 1.05, 1.3, 3.9, 0, 0.012, M["rug"], bevel=0.004)
cyl("Table_Base", (tx, ty, 0.02), 0.25, 0.016, M["chrome"])
cyl("Table_Pole", (tx, ty, 0.22), 0.028, 0.39, M["chrome"])
cyl("Table_Top", (tx, ty, 0.425), 0.48, 0.012, M["glass_table"], verts=128)
box("Book1", tx + 0.05, tx + 0.29, ty - 0.2, ty + 0.0, 0.431, 0.451, M["alu_black"], bevel=0.002)
box("Book2", tx + 0.07, tx + 0.27, ty - 0.18, ty - 0.03, 0.451, 0.468, M["quartz"], bevel=0.002)

box("Ottoman", 0.32, 0.82, 2.1, 2.6, 0.03, 0.44, M["leather"], bevel=0.04, segments=6)
box("Ottoman_Plinth", 0.36, 0.78, 2.14, 2.56, 0.0, 0.03, M["chrome"])


# ---------------------------------------------------------------- растения
def plant(name, x, y, z, pot_r, pot_h, height, leaves, leaf_len, spread=0.6):
    pot = cyl(f"{name}_Pot", (x, y, z + pot_h / 2), pot_r, pot_h, M["pot"])
    mod = pot.modifiers.new("Bevel", "BEVEL")
    mod.width = min(0.01, pot_r * 0.1)
    mod.segments = 3
    cyl(f"{name}_Soil", (x, y, z + pot_h - 0.01), pot_r * 0.93, 0.01, M["soil"])
    base = Vector((x, y, z + pot_h - 0.01))
    for i in range(leaves):
        ang = i * 2.39996 + random.uniform(-0.3, 0.3)  # золотой угол
        h = height * random.uniform(0.55, 1.0)
        r = height * spread * random.uniform(0.4, 0.8)
        tip = base + Vector((math.cos(ang) * r, math.sin(ang) * r, h))
        rod(f"{name}_Stem{i}", base, tip, max(0.003, leaf_len * 0.025), M["stem"])
        out = Vector((math.cos(ang), math.sin(ang), -0.35)).normalized()
        L = leaf_len * random.uniform(0.75, 1.1)
        ellipsoid(f"{name}_Leaf{i}", tip + out * L * 0.45, (L * 0.5, L * 0.36, L * 0.03), M["leaf"], rot_dir=out)


plant("Monstera", -1.72, 4.4, 0.0, 0.2, 0.45, 1.1, 11, 0.32)
plant("LedgePlantA", 0.95, D - 0.14, SILL, 0.07, 0.14, 0.32, 7, 0.08)
plant("LedgePlantB", 1.5, D - 0.14, SILL, 0.06, 0.12, 0.42, 6, 0.07, spread=0.3)
plant("TablePlant", tx - 0.2, ty + 0.12, 0.431, 0.05, 0.09, 0.14, 6, 0.05)

# ---------------------------------------------------------------- кот на подоконнике (спиной к камере, как в референсе)
cx, cy, cz = -1.15, D - 0.15, SILL
ellipsoid("Cat_Body", (cx, cy, cz + 0.13), (0.1, 0.09, 0.14), M["cat"])
ellipsoid("Cat_Haunch", (cx, cy - 0.01, cz + 0.06), (0.12, 0.11, 0.07), M["cat"])
ellipsoid("Cat_Head", (cx, cy + 0.02, cz + 0.32), (0.075, 0.07, 0.065), M["cat"])
for s in (-1, 1):
    bpy.ops.mesh.primitive_cone_add(radius1=0.028, depth=0.06, location=(cx + s * 0.042, cy + 0.02, cz + 0.39))
    ear = bpy.context.active_object
    ear.rotation_euler = (0, s * math.radians(-15), 0)
    ear.data.materials.append(M["cat"])
tail = [Vector((cx + 0.08, cy - 0.06, cz + 0.02)), Vector((cx + 0.18, cy - 0.12, cz + 0.015)),
        Vector((cx + 0.26, cy - 0.1, cz + 0.015))]
for i in range(len(tail) - 1):
    rod(f"Cat_Tail{i}", tail[i], tail[i + 1], 0.018, M["cat"], verts=12)

# ---------------------------------------------------------------- свет
# линейные светильники в потолке
for s in (-1, 1):
    box(f"CeilingLED{s}", s * 1.3 - 0.015, s * 1.3 + 0.015, 0.6, 4.6, H - 0.012, H, M["led_neutral"])

# кольцевая подвесная люстра вместо абажура
lx, ly, lz = tx, ty, 2.15
bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.016, major_segments=128,
                                 minor_segments=16, location=(lx, ly, lz))
ring = bpy.context.active_object
ring.name = "RingPendant_Housing"
ring.data.materials.append(M["alu_black"])
bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.009, major_segments=128,
                                 minor_segments=12, location=(lx, ly, lz - 0.012))
glow = bpy.context.active_object
glow.name = "RingPendant_LED"
glow.data.materials.append(M["led_warm"])
for k in range(3):
    a = k * 2 * math.pi / 3
    p = Vector((lx + math.cos(a) * 0.42, ly + math.sin(a) * 0.42, lz + 0.016))
    rod(f"RingWire{k}", p, (p.x, p.y, H), 0.0012, M["chrome"], verts=6)

# солнце через окна
sun_dir = Vector((-0.35, -0.85, -0.42)).normalized()
bpy.ops.object.light_add(type="SUN", location=(0, D + 3, 4))
sun = bpy.context.active_object
sun.data.energy = 4.5
sun.data.angle = math.radians(0.6)
sun.data.color = (1.0, 0.95, 0.88)
sun.rotation_mode = "QUATERNION"
sun.rotation_quaternion = sun_dir.to_track_quat("-Z", "Y")

# порталы в окнах: Cycles целенаправленно сэмплирует небо через проёмы
for n, (a, b) in enumerate(WINDOWS):
    bpy.ops.object.light_add(type="AREA", location=((a + b) / 2, D + 0.12, (SILL + WIN_TOP) / 2),
                             rotation=(math.radians(-90), 0, 0))
    portal = bpy.context.active_object
    portal.data.shape = "RECTANGLE"
    portal.data.size = b - a
    portal.data.size_y = WIN_TOP - SILL
    if hasattr(portal.data, "cycles") and hasattr(portal.data.cycles, "is_portal"):
        portal.data.cycles.is_portal = True
    elif hasattr(portal.data, "is_portal"):
        portal.data.is_portal = True

# мягкий заполняющий свет со стороны камеры
bpy.ops.object.light_add(type="AREA", location=(0, -0.4, 2.2), rotation=(math.radians(75), 0, 0))
fill = bpy.context.active_object
fill.data.size = 3.0
fill.data.energy = 120
fill.data.color = (1.0, 0.93, 0.85)
fill.visible_camera = False

# ---------------------------------------------------------------- окружение: физическое небо
world = scene.world or bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
wnt = world.node_tree
bg = wnt.nodes.get("Background")
try:
    sky = wnt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_disc = False
    sky.sun_elevation = math.asin(-sun_dir.z)
    sky.sun_rotation = math.atan2(-sun_dir.y, -sun_dir.x)
    sky.air_density = 1.0
    sky.dust_density = 1.5
    wnt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35
except Exception:
    bg.inputs["Color"].default_value = (0.55, 0.7, 0.95, 1.0)
    bg.inputs["Strength"].default_value = 1.5

# ---------------------------------------------------------------- камера
bpy.ops.object.camera_add(location=(0.0, -0.1, 1.3), rotation=(math.radians(87), 0, 0))
cam = bpy.context.active_object
cam.data.lens = 18
cam.data.sensor_width = 36
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = 2.8
cam.data.dof.aperture_fstop = 8.0
scene.camera = cam

# ---------------------------------------------------------------- рендер
scene.render.engine = "CYCLES"
scene.cycles.samples = 512
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 10
scene.cycles.caustics_reflective = False
scene.cycles.caustics_refractive = False
scene.render.resolution_x = 1600
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100

try:
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    scene.view_settings.view_transform = "Filmic"
    scene.view_settings.look = "Medium High Contrast"
scene.view_settings.exposure = 0.3

# GPU, если есть
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
        try:
            prefs.compute_device_type = backend
        except TypeError:
            continue
        prefs.get_devices()
        gpus = [d for d in prefs.devices if d.type != "CPU"]
        if gpus:
            for d in prefs.devices:
                d.use = True
            scene.cycles.device = "GPU"
            print(f"[hitech_room] GPU: {backend}, {len(gpus)} device(s)")
            break
except Exception as e:
    print(f"[hitech_room] GPU не подключён, рендер на CPU: {e}")

out_dir = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.getcwd()
scene.render.filepath = os.path.join(out_dir, "hitech_room.png")

if bpy.app.background:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "hitech_room.blend"))
    bpy.ops.render.render(write_still=True)
    print(f"[hitech_room] готово: {scene.render.filepath}")
