extends Node
## Прогресс игрока: открытые миссии и лучшие результаты.

const PATH := "user://progress.cfg"

var unlocked: int = 1            # сколько миссий открыто (1..3)
var best: Dictionary = {}        # mission_id -> {score:int, stars:int, grade:String}


func _ready() -> void:
	load_progress()


func best_for(mission_id: String) -> Dictionary:
	return best.get(mission_id, {})


## Записывает результат. Возвращает true, если это новый рекорд.
func record(mission_index: int, mission_id: String, score: int, stars: int, grade: String) -> bool:
	unlocked = clampi(maxi(unlocked, mission_index + 2), 1, 3)
	var prev: Dictionary = best.get(mission_id, {})
	var is_record := prev.is_empty() or score > int(prev.get("score", 0))
	if is_record:
		best[mission_id] = {"score": score, "stars": stars, "grade": grade}
	save_progress()
	return is_record


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	for id in best:
		cfg.set_value("best", id, best[id])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Save: не удалось сохранить прогресс (%s)" % error_string(err))


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	unlocked = clampi(int(cfg.get_value("progress", "unlocked", 1)), 1, 3)
	best.clear()
	if cfg.has_section("best"):
		for id in cfg.get_section_keys("best"):
			var v = cfg.get_value("best", id, {})
			if v is Dictionary:
				best[id] = v


func reset_progress() -> void:
	unlocked = 1
	best.clear()
	save_progress()
