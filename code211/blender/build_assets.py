"""
Генератор low-poly ассетов «Код 211» для Blender 4.x.

Запуск (из корня репозитория):
    blender -b -P code211/blender/build_assets.py -- --out code211/godot/assets/models
Опции:
    --only cop,bandit_heavy,pistol,shelf,police_car   собрать только перечисленное
    --blend                                             сохранить .blend рядом с .glb (для доработки художником)

Что получается (всё — .glb, Y-up, с материалами):
  персонажи  : cop, bandit_light, bandit_medium, bandit_heavy, cashier, customer
               + анимации idle/walk/run/aim/shoot/reload/cover/cover_blind/hit/death/
                 c_aim/c_shoot/c_reload/c_hit/arrested/stunned/hands_up/cower/threaten
  оружие     : weapons/pistol, weapons/baton  (узлы Slide/Mag/Muzzle)
  реквизит   : props/<shelf|shelf_wall|fridge|counter|crates|pallet|freezer|pillar|atm|display>
  транспорт  : police_car (узел DoorPivot)

Игра подхватывает файлы автоматически (CharacterRig/PoliceCar/LevelBuilder/Viewmodel);
если файла нет или в нём не хватает обязательных узлов/клипов — используется
встроенная процедурная модель, так что сломать игру ассетом нельзя.
"""

import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec  # noqa: E402
import bl_utils as U  # noqa: E402

FPS = 30


def build_character(kind, out_dir, save_blend):
    U.reset_scene()
    look = spec.LOOKS[kind]
    root = U.empty(kind)
    nodes = {}
    for name in spec.PIVOTS:  # порядок PIVOTS гарантирует, что родитель создан раньше
        parent, offset = spec.PIVOT_TREE[name]
        nodes[name] = U.empty(name, nodes[parent] if parent else root, offset)
    for i, (parent, size, pos, col) in enumerate(spec.character_parts(kind)):
        U.box("%s_part%02d" % (parent, i), size, pos, U.material(col), nodes[parent])
    if look["armed"]:
        socket = U.empty("WeaponSocket", nodes["elbow_r"], (0, -0.33, 0))
        socket.rotation_euler = U.euler_g2b((-1.5707963, 0, 0))
        long_gun = kind == "bandit_heavy"
        dark = U.material("1b1c1f", roughness=0.4)
        if long_gun:
            U.box("gun_body", (0.05, 0.07, 0.5), (0, 0.03, -0.18), dark, socket)
            U.box("gun_stock", (0.04, 0.12, 0.05), (0, -0.04, 0.02), U.material("3a2c22"), socket)
        else:
            U.box("gun_slide", (0.04, 0.05, 0.19), (0, 0.03, -0.06), dark, socket)
            U.box("gun_grip", (0.035, 0.1, 0.05), (0, -0.03, 0.02), dark, socket)
        U.empty("Muzzle", socket, (0, 0.03, -0.45 if long_gun else -0.18))

    # Клипы: по одному действию на шарнир, затем всё в NLA-треки с именем клипа.
    for clip_name, (length, keys) in spec.clips(look["armed"]).items():
        cyclic = clip_name in spec.LOOPING
        for pv in spec.PIVOTS:
            obj = nodes[pv]
            obj.animation_data_create()
            action = bpy.data.actions.new("%s|%s" % (clip_name, pv))
            obj.animation_data.action = action
            for t, pose in keys:
                frame = 1 + round(t * FPS)
                U.key_rotation(obj, frame, pose[pv])
                if pv == "hips":
                    U.key_height(obj, frame, pose["hips_y"])
            U.set_linear_or_loop(action, cyclic)
            U.push_action_to_nla(obj, action, clip_name)
    # Нейтральная поза в покое (важно для glTF: базовая трансформация узлов).
    for pv in spec.PIVOTS:
        nodes[pv].rotation_euler = (0, 0, 0)
    U.set_height(nodes["hips"], 0.95)
    tris = U.triangle_count()
    path = os.path.join(out_dir, kind + ".glb")
    U.export_glb(path)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, kind + ".blend"))
    print("[character] %-14s %5d tris  %d clips -> %s" % (kind, tris, len(spec.clips(look["armed"])), path))


def build_weapon(kind, out_dir, save_blend):
    U.reset_scene()
    root = U.empty(kind)
    groups = {}
    for name, size, pos, col in spec.WEAPONS[kind]:
        if name not in groups:
            groups[name] = U.empty(name, root)
        U.box(name + "_mesh", size, pos, U.material(col, roughness=0.45, metallic=0.3), groups[name])
    U.empty("Muzzle", root, spec.WEAPON_MUZZLE[kind])
    path = os.path.join(out_dir, "weapons", kind + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    U.export_glb(path)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=path.replace(".glb", ".blend"))
    print("[weapon]    %-14s %5d tris -> %s" % (kind, U.triangle_count(), path))


def build_prop(kind, out_dir, save_blend):
    U.reset_scene()
    root = U.empty(kind)
    for name, size, pos, col, emit in spec.prop_parts(kind):
        U.box(name, size, pos, U.material(col, emission=emit), root)
    path = os.path.join(out_dir, "props", kind + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    U.export_glb(path)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=path.replace(".glb", ".blend"))
    print("[prop]      %-14s %5d tris -> %s" % (kind, U.triangle_count(), path))


def build_police_car(out_dir, save_blend):
    U.reset_scene()
    root = U.empty("police_car")
    door = U.empty("DoorPivot", root, spec.CAR_DOOR_PIVOT)
    for parent, size, pos, col, emit in spec.CAR_PARTS:
        U.box("car_part", size, pos, U.material(col, emission=emit, roughness=0.35), door if parent else root)
    wheel_mat = U.material("0d0d0d", roughness=0.9)
    for i, wp in enumerate(spec.CAR_WHEELS):
        U.cylinder("wheel_%d" % i, 0.34, 0.24, wp, wheel_mat, root, vertices=12, axis="x")
    path = os.path.join(out_dir, "police_car.glb")
    U.export_glb(path)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=path.replace(".glb", ".blend"))
    print("[vehicle]   police_car     %5d tris -> %s" % (U.triangle_count(), path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--blend", action="store_true")
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    errors = spec.validate()
    if errors:
        print("Ошибки спецификации:\n" + "\n".join(errors))
        sys.exit(1)
    want = (lambda n: not only or n in only)
    for kind in spec.LOOKS:
        if want(kind):
            build_character(kind, out, args.blend)
    for kind in spec.WEAPONS:
        if want(kind):
            build_weapon(kind, out, args.blend)
    for kind in spec.PROPS:
        if want(kind):
            build_prop(kind, out, args.blend)
    if want("police_car"):
        build_police_car(out, args.blend)
    print("Готово: %s" % out)


if __name__ == "__main__":
    main()
