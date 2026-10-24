class_name MissionDB
extends RefCounted
## Описание трёх миссий: геометрия магазина, реквизит, грабители, гражданские,
## освещение и параметры вступительного ролика.
##
## Система координат: торговый зал x ∈ [-W/2, W/2], z ∈ [-D, 0];
## фасад (z = 0) смотрит на улицу (+Z). Углы реквизита — только 0/90/180/270
## (на этом строится автогенерация укрытий).

static func count() -> int:
	return all().size()


static func get_mission(index: int) -> Dictionary:
	var list := all()
	return list[clampi(index, 0, list.size() - 1)]


static func all() -> Array:
	return [_corner_shop(), _night_bodega(), _downtown()]


# ---------------------------------------------------------------- 1. Угловой магазин

static func _corner_shop() -> Dictionary:
	var props := []
	# Три прохода из низких стеллажей (вдоль Z).
	for x in [-3.9, -1.2, 1.5]:
		props.append({"kind": "shelf", "pos": Vector3(x, 0, -4.4), "rot": 90})
		props.append({"kind": "shelf", "pos": Vector3(x, 0, -6.9), "rot": 90})
	# Высокие пристенные стеллажи слева, холодильники у задней стены.
	for z in [-2.6, -5.2, -7.8]:
		props.append({"kind": "shelf_wall", "pos": Vector3(-6.7, 0, z), "rot": 90})
	for x in [-4.6, -2.8, -1.0, 0.8]:
		props.append({"kind": "fridge", "pos": Vector3(x, 0, -9.55), "rot": 0})
	props.append({"kind": "counter", "pos": Vector3(4.6, 0, -3.2), "rot": 90})
	props.append({"kind": "display", "pos": Vector3(-1.2, 0, -2.4), "rot": 0})
	props.append({"kind": "crates", "pos": Vector3(4.8, 0, -8.3), "rot": 0})
	props.append({"kind": "crates", "pos": Vector3(3.4, 0, -8.9), "rot": 90})
	props.append({"kind": "freezer", "pos": Vector3(4.2, 0, -6.0), "rot": 90})
	return {
		"id": "corner_shop",
		"title": "Угловой магазин",
		"caption": "14:20 · ул. Садовая, 7",
		"brief": "Дневной вызов. Трое грабителей в лёгкой экипировке держат кассира на прицеле. Тесный зал, три прохода.",
		"mood": "day",
		"size": Vector2(14, 10),
		"doors": [-4.4],
		"windows": [[-6.4, -5.4], [-3.3, 3.2], [4.2, 6.4]],
		"walls": [],
		"props": props,
		"bandits": [
			{"armor": "light", "role": "threaten", "pos": Vector3(3.2, 0, -3.2), "face": -90.0},
			{"armor": "light", "role": "patrol", "pos": Vector3(0.1, 0, -8.4), "face": 90.0,
				"patrol": [Vector3(0.1, 0, -8.4), Vector3(-2.6, 0, -8.4), Vector3(-2.6, 0, -3.0), Vector3(0.1, 0, -3.0)]},
			{"armor": "light", "role": "guard", "pos": Vector3(-2.4, 0, -1.4), "face": 30.0,
				"patrol": [Vector3(-2.4, 0, -1.4), Vector3(2.4, 0, -1.6)]},
		],
		"civilians": [{"kind": "cashier", "pos": Vector3(5.8, 0, -3.2), "face": 90.0}],
		"lights": [Vector3(-3.5, 0, -2.5), Vector3(1.5, 0, -2.5), Vector3(-3.5, 0, -7.0), Vector3(1.5, 0, -7.0), Vector3(5.2, 0, -5.0)],
		"light_color": Color(1.0, 0.97, 0.92),
		"light_energy": 0.42,
		"sign": "ПРОДУКТЫ",
		"sign_color": Color(1.0, 0.75, 0.2),
	}


# ---------------------------------------------------------------- 2. Ночная бодега

static func _night_bodega() -> Dictionary:
	var props := []
	for z in [-3.4, -5.9]:
		props.append({"kind": "shelf", "pos": Vector3(-0.6, 0, z), "rot": 90})
		props.append({"kind": "shelf", "pos": Vector3(2.0, 0, z), "rot": 90})
	for z in [-2.6, -4.4, -6.2]:
		props.append({"kind": "fridge", "pos": Vector3(4.55, 0, z), "rot": 270})
	props.append({"kind": "counter", "pos": Vector3(-3.4, 0, -2.4), "rot": 90})
	props.append({"kind": "shelf_wall", "pos": Vector3(-4.7, 0, -5.8), "rot": 90})
	props.append({"kind": "atm", "pos": Vector3(-4.6, 0, -7.6), "rot": 90})
	# Подсобка за перегородкой (z < -8.5).
	props.append({"kind": "crates", "pos": Vector3(-3.6, 0, -10.9), "rot": 0})
	props.append({"kind": "crates", "pos": Vector3(-1.4, 0, -11.3), "rot": 90})
	props.append({"kind": "crates", "pos": Vector3(3.8, 0, -10.2), "rot": 0})
	props.append({"kind": "pallet", "pos": Vector3(0.7, 0, -11.2), "rot": 0})
	return {
		"id": "night_bodega",
		"title": "Ночная бодега",
		"caption": "02:47 · пр. Мира, 112",
		"brief": "Ночь, тусклый свет, подсобка за перегородкой. Четверо, двое в бронежилетах. В зале заложник-покупатель.",
		"mood": "night",
		"size": Vector2(10, 12),
		"doors": [1.6],
		"windows": [[-4.6, -2.0], [2.6, 4.6]],
		# Перегородка подсобки: от x=-5 до x=1 и от x=2.7 до x=5 (проём 1.0…2.7).
		"walls": [{"from": Vector2(-5, -8.5), "to": Vector2(1.0, -8.5)}, {"from": Vector2(2.7, -8.5), "to": Vector2(5, -8.5)}],
		"props": props,
		"bandits": [
			{"armor": "light", "role": "threaten", "pos": Vector3(-2.2, 0, -2.4), "face": 90.0},
			{"armor": "medium", "role": "patrol", "pos": Vector3(0.7, 0, -7.4), "face": 0.0,
				"patrol": [Vector3(0.7, 0, -7.4), Vector3(0.7, 0, -2.4), Vector3(3.3, 0, -2.4), Vector3(3.3, 0, -7.4)]},
			{"armor": "light", "role": "loot", "pos": Vector3(-2.2, 0, -10.0), "face": 180.0},
			{"armor": "medium", "role": "guard", "pos": Vector3(3.4, 0, -1.4), "face": 0.0},
		],
		"civilians": [
			{"kind": "cashier", "pos": Vector3(-4.5, 0, -2.4), "face": -90.0},
			{"kind": "customer", "pos": Vector3(-2.4, 0, -7.0), "face": 0.0},
		],
		"lights": [Vector3(-2.0, 0, -3.0), Vector3(2.4, 0, -3.5), Vector3(0.8, 0, -7.0), Vector3(-1.5, 0, -10.5), Vector3(3.0, 0, -10.5)],
		"flicker": [2],
		"light_color": Color(0.85, 0.95, 1.0),
		"light_energy": 0.5,
		"sign": "24 ЧАСА",
		"sign_color": Color(1.0, 0.2, 0.55),
	}


# ---------------------------------------------------------------- 3. Даунтаун-маркет

static func _downtown() -> Dictionary:
	var props := []
	for z in [-9.0, -12.6]:
		for x in [-7.8, -5.2, 5.2, 7.8]:
			props.append({"kind": "shelf", "pos": Vector3(x, 0, z), "rot": 0})
	for p in [Vector3(-2.9, 0, -6.2), Vector3(2.9, 0, -6.2), Vector3(-2.9, 0, -11.8), Vector3(2.9, 0, -11.8)]:
		props.append({"kind": "pillar", "pos": p, "rot": 0})
	props.append({"kind": "freezer", "pos": Vector3(0, 0, -9.0), "rot": 90})
	props.append({"kind": "freezer", "pos": Vector3(0, 0, -13.0), "rot": 90})
	for x in [-7.2, -5.4, -3.6, -1.8, 1.8, 3.6, 5.4, 7.2]:
		props.append({"kind": "fridge", "pos": Vector3(x, 0, -15.55), "rot": 0})
	props.append({"kind": "counter", "pos": Vector3(-2.6, 0, -3.0), "rot": 0})
	props.append({"kind": "counter", "pos": Vector3(2.6, 0, -3.0), "rot": 0})
	props.append({"kind": "atm", "pos": Vector3(-9.55, 0, -2.4), "rot": 90})
	props.append({"kind": "display", "pos": Vector3(-8.2, 0, -5.4), "rot": 0})
	props.append({"kind": "display", "pos": Vector3(8.2, 0, -5.4), "rot": 0})
	props.append({"kind": "crates", "pos": Vector3(-9.0, 0, -14.0), "rot": 0})
	props.append({"kind": "crates", "pos": Vector3(9.0, 0, -13.8), "rot": 90})
	return {
		"id": "downtown",
		"title": "Даунтаун-маркет",
		"caption": "19:05 · Центральная пл., 3",
		"brief": "Большой зал, колонны, два входа. Пятеро, у двоих тяжёлая броня и шлемы — цельтесь в незащищённые места или берите живыми.",
		"mood": "rain",
		"size": Vector2(20, 16),
		"doors": [-6.0, 6.0],
		"windows": [[-9.6, -7.2], [-4.8, 4.8], [7.2, 9.6]],
		"walls": [],
		"props": props,
		"bandits": [
			{"armor": "heavy", "role": "threaten", "pos": Vector3(2.6, 0, -4.4), "face": 180.0},
			{"armor": "medium", "role": "patrol", "pos": Vector3(-6.5, 0, -10.8), "face": 90.0,
				"patrol": [Vector3(-6.5, 0, -10.8), Vector3(6.5, 0, -10.8)]},
			{"armor": "light", "role": "loot", "pos": Vector3(-1.4, 0, -14.4), "face": 0.0},
			{"armor": "light", "role": "guard", "pos": Vector3(-6.0, 0, -2.0), "face": 20.0,
				"patrol": [Vector3(-6.0, 0, -2.0), Vector3(-6.0, 0, -7.4)]},
			{"armor": "heavy", "role": "guard", "pos": Vector3(7.0, 0, -7.4), "face": -20.0,
				"patrol": [Vector3(7.0, 0, -7.4), Vector3(7.0, 0, -2.2)]},
		],
		"civilians": [{"kind": "cashier", "pos": Vector3(2.6, 0, -1.9), "face": 0.0}],
		"lights": [Vector3(-6.0, 0, -3.5), Vector3(0, 0, -3.5), Vector3(6.0, 0, -3.5), Vector3(-6.0, 0, -9.0),
			Vector3(0, 0, -9.5), Vector3(6.0, 0, -9.0), Vector3(-5.0, 0, -14.0), Vector3(5.0, 0, -14.0)],
		"light_color": Color(1.0, 0.95, 0.88),
		"light_energy": 0.55,
		"sign": "МАРКЕТ",
		"sign_color": Color(0.3, 0.85, 1.0),
	}
