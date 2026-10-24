extends Node
## Глобальные настройки: графика, звук, управление, сложность.
## Хранятся в user://settings.cfg, применяются сразу при изменении (apply()).
## Миссия подписывается на `changed`, чтобы перестроить тени/свечение/туман.

signal changed

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }
enum ShadowQuality { OFF, LOW, HIGH }
enum Difficulty { EASY, NORMAL, HARD }

const QUALITY_NAMES := ["Низкое", "Среднее", "Высокое"]
const SHADOW_NAMES := ["Выкл", "Низкие", "Высокие"]
const DIFFICULTY_NAMES := ["Новичок", "Патрульный", "Спецназ"]

var quality: int = Quality.MEDIUM
var shadow_quality: int = ShadowQuality.LOW
var fps_cap: int = 60
var master_volume: float = 0.9
var music_volume: float = 0.6
var sfx_volume: float = 1.0
var look_sensitivity: float = 1.0
var invert_y: bool = false
var aim_assist: bool = true
var difficulty: int = Difficulty.NORMAL


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_ensure_input_actions()
	load_settings()
	apply()


# ---------------------------------------------------------------- графика

func render_scale() -> float:
	return [0.7, 0.85, 1.0][quality]


func msaa() -> int:
	return [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]


func glow_enabled() -> bool:
	return quality >= Quality.MEDIUM


func fog_enabled() -> bool:
	return quality >= Quality.MEDIUM


func rain_enabled() -> bool:
	return quality >= Quality.MEDIUM


func shadows_enabled() -> bool:
	return shadow_quality != ShadowQuality.OFF


## Тени от точечных ламп дорогие на мобильных GPU — только на «Высоких».
func omni_shadows_enabled() -> bool:
	return shadow_quality == ShadowQuality.HIGH


func directional_shadow_size() -> int:
	return 4096 if shadow_quality == ShadowQuality.HIGH else 2048


func apply() -> void:
	Engine.max_fps = fps_cap
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale()
		vp.msaa_3d = msaa()
		vp.positional_shadow_atlas_size = 2048 if omni_shadows_enabled() else 1024
	RenderingServer.directional_shadow_atlas_set_size(directional_shadow_size(), true)
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	changed.emit()


# ---------------------------------------------------------------- хранение

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "shadows", shadow_quality)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "aim_assist", aim_assist)
	cfg.set_value("game", "difficulty", difficulty)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: не удалось сохранить (%s)" % error_string(err))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # первый запуск — остаются значения по умолчанию
	# Любое значение зажимается в допустимый диапазон: битый файл не ломает игру.
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, 2)
	shadow_quality = clampi(int(cfg.get_value("graphics", "shadows", shadow_quality)), 0, 2)
	fps_cap = 30 if int(cfg.get_value("graphics", "fps_cap", fps_cap)) == 30 else 60
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	look_sensitivity = clampf(float(cfg.get_value("controls", "sensitivity", look_sensitivity)), 0.3, 2.5)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	aim_assist = bool(cfg.get_value("controls", "aim_assist", aim_assist))
	difficulty = clampi(int(cfg.get_value("game", "difficulty", difficulty)), 0, 2)


# ---------------------------------------------------------------- служебное

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Клавиатура/мышь — для отладки на Mac/ПК. На iPhone всё идёт через TouchControls.
func _ensure_input_actions() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"reload": [KEY_R],
		"switch_weapon": [KEY_Q, KEY_1],
		"crouch": [KEY_C, KEY_CTRL],
		"pause": [KEY_ESCAPE, KEY_P],
		"skip": [KEY_SPACE, KEY_ENTER],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
