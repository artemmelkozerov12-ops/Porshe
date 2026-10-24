"""
Спецификация ассетов «Код 211» — единый источник данных для Blender-генератора.

Зеркалирует процедурные модели игры (godot/scripts/gameplay/character_rig.gd,
level_builder.gd, police_car.gd, viewmodel.gd). Имена узлов и клипов —
контракт с игрой: CharacterRig ищет AnimationPlayer с клипами из REQUIRED_ANIMS.

Все координаты здесь — в системе Godot (Y вверх, персонаж смотрит в -Z).
Перевод в Blender (Z вверх) делает bl_utils.g2b(); экспортёр glTF переводит обратно.
Чистый Python, без bpy — модуль можно импортировать и тестировать вне Blender.
"""

from math import sin, cos, pi, tau

# ---------------------------------------------------------------------------
# Персонажи
# ---------------------------------------------------------------------------

PIVOTS = ["hips", "spine", "neck", "shoulder_l", "elbow_l", "shoulder_r", "elbow_r",
          "hip_l", "knee_l", "hip_r", "knee_r"]

# Иерархия шарниров: имя -> (родитель, смещение от родителя).
PIVOT_TREE = {
    "hips": (None, (0.0, 0.95, 0.0)),
    "spine": ("hips", (0.0, 0.08, 0.0)),
    "neck": ("spine", (0.0, 0.52, 0.0)),
    "shoulder_l": ("spine", (-0.26, 0.46, 0.0)),
    "elbow_l": ("shoulder_l", (0.0, -0.29, 0.0)),
    "shoulder_r": ("spine", (0.26, 0.46, 0.0)),
    "elbow_r": ("shoulder_r", (0.0, -0.29, 0.0)),
    "hip_l": ("hips", (-0.1, -0.05, 0.0)),
    "knee_l": ("hip_l", (0.0, -0.44, 0.0)),
    "hip_r": ("hips", (0.1, -0.05, 0.0)),
    "knee_r": ("hip_r", (0.0, -0.44, 0.0)),
}

REQUIRED_ANIMS = ["idle", "walk", "run", "aim", "shoot", "reload", "cover", "hit", "death"]
LOOPING = {"idle", "idle_unarmed", "walk", "run", "aim", "cover", "c_aim", "hands_up",
           "threaten", "stunned", "cower"}

SKIN = "c69c7b"

LOOKS = {
    "cop": dict(top="1f2d4d", bottom="161d2c", head=SKIN, shoes="101010", armed=True, gear="cop"),
    "bandit_light": dict(top="3b4048", bottom="2d3953", head="151515", shoes="d8d8d8", armed=True, gear="mask"),
    "bandit_medium": dict(top="33352f", bottom="2b2f26", head="151515", shoes="2a2a2a", armed=True, gear="vest"),
    "bandit_heavy": dict(top="232528", bottom="1d1f22", head="151515", shoes="1a1a1a", armed=True, gear="heavy"),
    "cashier": dict(top="b8323a", bottom="2b2f3a", head="d1a684", shoes="2a2a2a", armed=False, gear="apron"),
    "customer": dict(top="6b5b45", bottom="39404d", head="b88a68", shoes="4a3a2a", armed=False, gear=""),
}


def character_parts(kind):
    """Список коробок: (родитель-шарнир, размер, позиция, цвет-hex)."""
    lk = LOOKS[kind]
    gear = lk["gear"]
    masked = gear in ("mask", "vest", "heavy")
    skin = "d1a684" if gear == "apron" else SKIN
    head = lk["head"] if masked else skin
    p = [
        ("hips", (0.34, 0.18, 0.2), (0, 0, 0), lk["bottom"]),
        ("spine", (0.4, 0.5, 0.24), (0, 0.27, 0), lk["top"]),
        ("neck", (0.1, 0.08, 0.1), (0, 0.03, 0), head),
        ("neck", (0.22, 0.25, 0.24), (0, 0.17, 0), head),
    ]
    if gear == "cop":
        p += [("neck", (0.25, 0.07, 0.27), (0, 0.31, 0), "18233d"),
              ("neck", (0.24, 0.02, 0.1), (0, 0.28, -0.16), "101010"),
              ("neck", (0.05, 0.05, 0.01), (0, 0.32, -0.14), "d4a93a"),
              ("spine", (0.06, 0.07, 0.01), (-0.1, 0.38, -0.125), "d4a93a"),
              ("hips", (0.36, 0.06, 0.22), (0, 0.07, 0), "0e0e0e")]
    if masked:
        p += [("neck", (0.2, 0.05, 0.02), (0, 0.2, -0.12), SKIN),
              ("neck", (0.14, 0.02, 0.005), (0, 0.2, -0.131), "1a1a1a")]
    if gear in ("vest", "heavy"):
        vest = "4a5236" if gear == "vest" else "2e3328"
        thick = 0.32 if gear == "vest" else 0.36
        p += [("spine", (0.44, 0.4, thick), (0, 0.3, 0), vest),
              ("spine", (0.3, 0.1, 0.06), (0, 0.18, -thick * 0.5 - 0.02), vest)]
    if gear == "heavy":
        p += [("neck", (0.27, 0.13, 0.29), (0, 0.28, 0), "3b4031"),
              ("neck", (0.22, 0.06, 0.02), (0, 0.22, -0.145), "101418")]
    if gear == "apron":
        p += [("spine", (0.38, 0.5, 0.02), (0, 0.15, -0.13), "2f6b4f"),
              ("neck", (0.23, 0.08, 0.25), (0, 0.29, 0.01), "3a2a1e")]
    elif not masked and gear != "cop":
        p += [("neck", (0.23, 0.07, 0.25), (0, 0.29, 0.01), "2a2018")]
    for s in ("l", "r"):
        p += [("shoulder_" + s, (0.11, 0.3, 0.12), (0, -0.14, 0), lk["top"]),
              ("elbow_" + s, (0.1, 0.27, 0.1), (0, -0.13, 0), lk["top"]),
              ("elbow_" + s, (0.09, 0.1, 0.1), (0, -0.31, 0), "151515" if gear == "heavy" else skin),
              ("hip_" + s, (0.15, 0.44, 0.16), (0, -0.22, 0), lk["bottom"]),
              ("knee_" + s, (0.13, 0.42, 0.14), (0, -0.21, 0), lk["bottom"]),
              ("knee_" + s, (0.13, 0.08, 0.25), (0, -0.44, -0.05), lk["shoes"])]
        if gear == "heavy":
            p.append(("shoulder_" + s, (0.15, 0.12, 0.16), (0, -0.02, 0), "2e3328"))
    return p


# --- Позы и клипы (порт CharacterRig._build_animations) ---------------------

def pose(**over):
    p = {"hips_y": 0.95}
    for k in PIVOTS:
        p[k] = (0.0, 0.0, 0.0)
    p.update(over)
    return p


def merge(base, over):
    p = dict(base)
    p.update(over)
    return p


ARMS_READY = dict(shoulder_r=(0.65, 0, -0.05), elbow_r=(0.55, 0, 0), shoulder_l=(0.55, 0, 0.3), elbow_l=(0.75, 0, 0))
ARMS_AIM = dict(shoulder_r=(1.5, 0, -0.08), elbow_r=(0.0, 0, 0), shoulder_l=(1.4, 0, 0.42), elbow_l=(0.15, 0, 0),
                spine=(-0.04, 0, 0))
ARMS_RELAXED = dict(shoulder_r=(0.05, 0, -0.08), shoulder_l=(0.05, 0, 0.08), elbow_r=(0.15, 0, 0), elbow_l=(0.15, 0, 0))
CROUCH = dict(hips_y=0.47, spine=(-0.45, 0, 0), neck=(0.25, 0, 0), hip_l=(1.6, 0, 0.05), knee_l=(-2.2, 0, 0),
              hip_r=(1.3, 0, -0.05), knee_r=(-2.05, 0, 0))


def clips(armed):
    """Возвращает {имя: (длина, [(время, поза), ...])}."""
    c = {}
    upper = ARMS_READY if armed else ARMS_RELAXED
    idle_a = pose(**upper)
    c["idle"] = (2.0, [(0, idle_a), (1.0, merge(idle_a, dict(spine=(0.03, 0, 0), hips_y=0.945))), (2.0, idle_a)])
    un = pose(**ARMS_RELAXED)
    c["idle_unarmed"] = (2.0, [(0, un), (1.0, merge(un, dict(spine=(0.03, 0, 0)))), (2.0, un)])
    for name, period, swing, knee, low, lean in (("walk", 0.9, 0.45, -0.65, 0.93, 0.0),
                                                   ("run", 0.6, 0.8, -1.25, 0.9, -0.22)):
        keys = []
        for i in range(5):
            ph = i / 4.0
            s, co = sin(ph * tau), cos(ph * tau)
            p = pose(**(upper if armed else {}))
            p["hip_l"] = (swing * s, 0, 0)
            p["hip_r"] = (-swing * s, 0, 0)
            p["knee_l"] = (knee * max(0.0, -co), 0, 0)
            p["knee_r"] = (knee * max(0.0, co), 0, 0)
            p["hips_y"] = 0.95 + (low - 0.95) * abs(s)
            p["spine"] = (lean, 0, 0)
            if not armed:
                p["shoulder_l"] = (-swing * 0.7 * s, 0, 0.08)
                p["shoulder_r"] = (swing * 0.7 * s, 0, -0.08)
                p["elbow_l"] = (0.3, 0, 0)
                p["elbow_r"] = (0.3, 0, 0)
            keys.append((ph * period, p))
        c[name] = (period, keys)
    aim = pose(**ARMS_AIM)
    c["aim"] = (1.6, [(0, aim), (0.8, merge(aim, dict(spine=(-0.02, 0, 0)))), (1.6, aim)])
    kick = merge(aim, dict(shoulder_r=(1.78, 0, -0.08), elbow_r=(0.2, 0, 0), shoulder_l=(1.62, 0, 0.42), spine=(0.04, 0, 0)))
    c["shoot"] = (0.22, [(0, aim), (0.05, kick), (0.22, aim)])
    low_r = merge(aim, dict(shoulder_r=(0.75, 0, -0.1), elbow_r=(1.1, 0, 0), shoulder_l=(0.9, 0, 0.35), elbow_l=(1.3, 0, 0)))
    fetch = merge(low_r, dict(shoulder_l=(0.15, 0, 0.15), elbow_l=(0.4, 0, 0)))
    c["reload"] = (1.6, [(0, aim), (0.3, low_r), (0.65, fetch), (1.05, low_r), (1.6, aim)])
    hit = merge(aim, dict(spine=(0.38, 0, 0.1), neck=(0.3, 0, 0), shoulder_l=(0.6, 0, 0.5)))
    c["hit"] = (0.32, [(0, aim), (0.08, hit), (0.32, aim)])
    c_aim = merge(aim, CROUCH)
    c["c_aim"] = (1.6, [(0, c_aim), (1.6, c_aim)])
    c["c_shoot"] = (0.22, [(0, c_aim), (0.05, merge(kick, CROUCH)), (0.22, c_aim)])
    c["c_reload"] = (1.6, [(0, c_aim), (0.3, merge(low_r, CROUCH)), (0.65, merge(fetch, CROUCH)),
                           (1.05, merge(low_r, CROUCH)), (1.6, c_aim)])
    c["c_hit"] = (0.32, [(0, c_aim), (0.08, merge(hit, CROUCH)), (0.32, c_aim)])
    cover = merge(pose(shoulder_r=(0.9, 0, -0.25), elbow_r=(1.4, 0, 0), shoulder_l=(0.8, 0, 0.35), elbow_l=(1.3, 0, 0)), CROUCH)
    c["cover"] = (2.0, [(0, cover), (1.0, merge(cover, dict(neck=(0.35, 0.15, 0)))), (2.0, cover)])
    blind = merge(cover, dict(shoulder_r=(2.6, 0, -0.1), elbow_r=(-1.0, 0, 0)))
    c["cover_blind"] = (0.3, [(0, blind), (0.06, merge(blind, dict(shoulder_r=(2.75, 0, -0.1)))), (0.3, blind)])
    d1 = merge(hit, dict(hips_y=0.75, spine=(0.5, 0, 0), knee_l=(-0.6, 0, 0), knee_r=(-0.4, 0, 0)))
    d2 = pose(hips_y=0.17, hips=(1.48, 0, 0.05), spine=(0.1, 0, 0), neck=(0.2, 0.4, 0), shoulder_l=(0.3, 0, 1.2),
              shoulder_r=(0.6, 0, -1.3), elbow_l=(0.4, 0, 0), elbow_r=(0.6, 0, 0), hip_l=(0.1, 0, 0.15),
              knee_l=(-0.3, 0, 0), hip_r=(0.35, 0, -0.1), knee_r=(-0.6, 0, 0))
    c["death"] = (1.1, [(0, aim), (0.25, d1), (0.9, d2), (1.1, d2)])
    kneel = pose(hips_y=0.5, hip_l=(0, 0, 0.05), knee_l=(-1.55, 0, 0), hip_r=(0, 0, -0.05), knee_r=(-1.55, 0, 0),
                 spine=(-0.1, 0, 0), neck=(0.3, 0, 0), shoulder_l=(0.3, 0, -2.5), elbow_l=(0, 0, 2.3),
                 shoulder_r=(0.3, 0, 2.5), elbow_r=(0, 0, -2.3))
    c["arrested"] = (1.0, [(0, hit), (0.6, kneel), (1.0, kneel)])
    stun = pose(**merge(CROUCH, dict(spine=(-0.7, 0, 0), shoulder_l=(2.3, 0, 0.5), elbow_l=(1.9, 0, 0),
                                     shoulder_r=(2.3, 0, -0.5), elbow_r=(1.9, 0, 0))))
    c["stunned"] = (1.2, [(0, stun), (0.6, merge(stun, dict(spine=(-0.6, 0.15, 0.1)))), (1.2, stun)])
    hands_up = pose(shoulder_l=(0.1, 0, -2.75), elbow_l=(0, 0, -0.25), shoulder_r=(0.1, 0, 2.75), elbow_r=(0, 0, 0.25),
                    neck=(0.1, 0, 0))
    c["hands_up"] = (1.4, [(0, hands_up), (0.7, merge(hands_up, dict(spine=(0.05, 0, 0)))), (1.4, hands_up)])
    cower = pose(**merge(CROUCH, dict(spine=(-0.8, 0, 0), shoulder_l=(2.4, 0, 0.6), elbow_l=(2.0, 0, 0),
                                      shoulder_r=(2.4, 0, -0.6), elbow_r=(2.0, 0, 0))))
    c["cower"] = (1.0, [(0, cower), (0.5, merge(cower, dict(spine=(-0.75, 0, 0)))), (1.0, cower)])
    jab = merge(aim, dict(shoulder_r=(1.62, 0, -0.08), spine=(-0.1, 0, 0)))
    c["threaten"] = (1.2, [(0, aim), (0.3, jab), (0.6, aim), (1.2, aim)])
    return c


# ---------------------------------------------------------------------------
# Оружие (вид от первого лица и в руках персонажей)
# ---------------------------------------------------------------------------

WEAPONS = {
    # Узлы "Slide", "Mag", "Muzzle" — контракт с Viewmodel (анимация затвора/магазина).
    "pistol": [
        ("Slide", (0.034, 0.038, 0.2), (0, 0.025, -0.05), "1d1f23"),
        ("Slide", (0.006, 0.012, 0.01), (0, 0.05, -0.145), "e8e8e8"),
        ("Frame", (0.03, 0.02, 0.17), (0, -0.003, -0.04), "15161a"),
        ("Grip", (0.032, 0.11, 0.045), (0, -0.06, 0.03), "15161a"),
        ("Mag", (0.026, 0.02, 0.038), (0, -0.122, 0.03), "1d1f23"),
    ],
    "baton": [
        ("Shaft", (0.032, 0.55, 0.032), (0, 0.27, 0), "101114"),
        ("Handle", (0.05, 0.11, 0.05), (0, -0.02, 0), "101114"),
    ],
}
WEAPON_MUZZLE = {"pistol": (0, 0.025, -0.17), "baton": (0, 0.55, 0)}


# ---------------------------------------------------------------------------
# Реквизит мини-маркета (размеры = коллайдеры в level_builder.gd)
# ---------------------------------------------------------------------------

PROPS = {
    "shelf": (2.4, 1.35, 0.8),
    "shelf_wall": (2.4, 2.0, 0.5),
    "fridge": (1.6, 2.1, 0.8),
    "counter": (2.6, 1.05, 0.8),
    "crates": (1.0, 1.1, 1.0),
    "pallet": (1.2, 1.4, 1.0),
    "freezer": (1.8, 0.95, 0.9),
    "pillar": (0.6, 3.0, 0.6),
    "atm": (0.7, 1.75, 0.6),
    "display": (1.0, 1.2, 0.6),
}


def prop_parts(kind):
    """Коробки реквизита: (имя, размер, позиция, цвет-hex, излучение 0..)."""
    sx, sy, sz = PROPS[kind]
    parts = []
    if kind == "shelf":
        parts += [("base", (sx, 0.1, sz), (0, 0.05, 0), "3a3d42", 0),
                  ("spine", (sx, sy - 0.1, 0.05), (0, sy / 2 + 0.05, 0), "b9bec4", 0)]
        for ex in (-sx / 2 + 0.02, sx / 2 - 0.02):
            parts.append(("end", (0.04, sy, sz), (ex, sy / 2, 0), "8c939b", 0))
        for side in (-1, 1):
            for y in (0.38, 0.78, 1.16):
                parts.append(("board", (sx - 0.08, 0.025, 0.36), (0, y, 0.2 * side), "d4d7db", 0))
    elif kind == "shelf_wall":
        parts.append(("back", (sx, sy, 0.04), (0, sy / 2, -sz / 2 + 0.02), "9aa1a8", 0))
        for y in (0.1, 0.5, 0.92, 1.34, 1.74):
            parts.append(("board", (sx - 0.04, 0.025, sz - 0.06), (0, y, 0.02), "d4d7db", 0))
    elif kind == "fridge":
        parts += [("body", (sx, sy, sz - 0.04), (0, sy / 2, -0.02), "e9ecef", 0),
                  ("glow", (sx - 0.12, sy - 0.32, 0.02), (0, sy / 2 - 0.06, sz / 2 - 0.01), "b8e0ff", 0.9),
                  ("header", (sx, 0.16, 0.04), (0, sy - 0.1, sz / 2), "ffb21e", 1.2)]
    elif kind == "counter":
        parts += [("body", (sx, sy - 0.05, sz), (0, (sy - 0.05) / 2, 0), "4a3f37", 0),
                  ("top", (sx + 0.1, 0.05, sz + 0.06), (0, sy - 0.025, 0), "d9d4cc", 0),
                  ("register", (0.42, 0.12, 0.38), (0.6, sy + 0.06, 0.05), "2a2c30", 0),
                  ("screen", (0.3, 0.2, 0.025), (0.6, sy + 0.32, -0.05), "4dff8c", 1.2)]
    elif kind == "crates":
        parts += [("box_a", (1.0, 0.55, 1.0), (0, 0.275, 0), "a9824f", 0),
                  ("box_b", (0.8, 0.5, 0.8), (0.05, 0.8, -0.02), "987546", 0)]
    elif kind == "pallet":
        parts += [("pallet", (sx, 0.14, sz), (0, 0.07, 0), "8a6a43", 0),
                  ("wrap", (sx - 0.1, sy - 0.16, sz - 0.06), (0, 0.14 + (sy - 0.16) / 2, 0), "b8c2c9", 0)]
    elif kind == "freezer":
        parts += [("body", (sx, sy - 0.05, sz), (0, (sy - 0.05) / 2, 0), "f1f3f5", 0),
                  ("lid", (sx - 0.1, 0.03, sz - 0.1), (0, sy - 0.03, 0), "99d9ff", 0.8)]
    elif kind == "pillar":
        parts += [("column", (sx, sy, sz), (0, sy / 2, 0), "a8a49c", 0),
                  ("base", (sx + 0.04, 0.2, sz + 0.04), (0, 0.1, 0), "4a4d52", 0)]
    elif kind == "atm":
        parts += [("body", (sx, sy, sz), (0, sy / 2, 0), "1f3b6e", 0),
                  ("screen", (0.36, 0.28, 0.02), (0, 1.25, sz / 2 + 0.01), "73ccff", 1.5)]
    elif kind == "display":
        parts += [("stand", (sx, sy, sz), (0, sy / 2, 0), "c0392b", 0),
                  ("topper", (sx, 0.25, 0.04), (0, sy + 0.15, 0), "f1c40f", 0)]
    return parts


# ---------------------------------------------------------------------------
# Патрульная машина (узел "DoorPivot" — контракт с PoliceCar)
# ---------------------------------------------------------------------------

CAR_PARTS = [
    (None, (1.85, 0.55, 4.6), (0, 0.62, 0), "eef0f2", 0),
    (None, (1.87, 0.2, 4.62), (0, 0.38, 0), "121314", 0),
    (None, (1.62, 0.5, 2.3), (0, 1.15, 0.2), "0c1622", 0),
    (None, (1.5, 0.06, 2.1), (0, 1.42, 0.25), "eef0f2", 0),
    (None, (0.55, 0.1, 0.26), (-0.3, 1.58, 0.1), "ff1a1a", 2.0),
    (None, (0.55, 0.1, 0.26), (0.3, 1.58, 0.1), "2659ff", 2.0),
    ("DoorPivot", (0.06, 0.55, 1.1), (0, 0.66, 0.55), "eef0f2", 0),
]
CAR_DOOR_PIVOT = (-0.94, 0.0, -0.45)
CAR_WHEELS = [(-0.86, 0.34, -1.45), (0.86, 0.34, -1.45), (-0.86, 0.34, 1.45), (0.86, 0.34, 1.45)]


def validate():
    """Самопроверка спецификации (запускается тестами без Blender)."""
    errors = []
    for k in LOOKS:
        for parent, size, pos, col in character_parts(k):
            if parent not in PIVOT_TREE:
                errors.append("%s: неизвестный шарнир %s" % (k, parent))
            if min(size) <= 0:
                errors.append("%s: нулевой размер" % k)
            if len(col) != 6:
                errors.append("%s: цвет %s" % (k, col))
    for armed in (True, False):
        cl = clips(armed)
        for req in REQUIRED_ANIMS:
            if req not in cl:
                errors.append("нет клипа %s" % req)
        for name, (length, keys) in cl.items():
            if keys[-1][0] > length + 1e-6:
                errors.append("%s: ключ за пределами длины" % name)
            for _, p in keys:
                missing = [pv for pv in PIVOTS if pv not in p]
                if missing:
                    errors.append("%s: нет шарниров %s" % (name, missing))
    for kind in PROPS:
        if not prop_parts(kind):
            errors.append("реквизит %s без деталей" % kind)
    return errors


if __name__ == "__main__":
    errs = validate()
    print("spec OK" if not errs else "\n".join(errs))
