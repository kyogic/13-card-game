extends Node
## The story's calendar: several days (data/story.json), each split into time slots;
## where each character is per slot (data/schedule.json, same every day); time costs
## (tuning.json -> time) and location locks.

const STORY_PATH := "res://data/story.json"
const SCHEDULE_PATH := "res://data/schedule.json"

var story: Dictionary = {}
var schedule: Dictionary = {}
var day_over := false          # the current day's slots are used up (summary showing)


func _init() -> void:
	story = _load(STORY_PATH)
	schedule = _load(SCHEDULE_PATH)


func _load(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func days() -> int:
	return int(story.get("days", 1))


## Day 1 of a new story: fresh state and the starter gifts.
func start_story() -> void:
	GameState.reset(story.get("starter_inventory", {}))
	GameState.day = 1
	GameState.money = Config.int_value("economy.start_money")
	for id in Characters.ids():
		Affection.ensure(id)
		GameState.char_state(id).story_start_affection = Affection.value(id)
	_begin_day()


## After a day's summary: move to the next morning.
func start_next_day() -> void:
	if not day_over or is_final_day():
		return
	GameState.day += 1
	_begin_day()


func _begin_day() -> void:
	for id in Characters.ids():
		var st: Dictionary = GameState.char_state(id)
		st.start_affection = Affection.value(id)
		st.start_unlocks = st.unlocks.duplicate()
	GameState.day_log = []
	GameState.day_start_money = GameState.money
	Economy.restock()
	day_over = false
	GameState.slot_index = 0
	GameState.location = ""
	GameState.time_left = units_per_slot()
	EventBus.fire("time_advanced", {"slot_index": 0, "time_left": GameState.time_left, "day": GameState.day})


func is_final_day() -> bool:
	return GameState.day >= days()


func story_over() -> bool:
	return day_over and is_final_day()


func slots() -> Array:
	return story.get("slots", [])


func slot() -> Dictionary:
	var all := slots()
	return all[GameState.slot_index] if GameState.slot_index < all.size() else {}


func slot_name() -> String:
	return slot().get("name", "")


func units_per_slot() -> int:
	return Config.int_value("time.units_per_slot", 3)


func cost(kind: String) -> int:
	return Config.int_value("time." + kind, 0)


func can_afford(kind: String) -> bool:
	return not day_over and GameState.time_left >= cost(kind)


## Spends the time for an action; when the slot runs out, moves to the next one.
func spend(kind: String) -> void:
	GameState.time_left -= cost(kind)
	if GameState.time_left <= 0:
		next_slot()


## A date (or waiting) uses up the rest of the slot.
func end_slot() -> void:
	next_slot()


func next_slot() -> void:
	if day_over:
		return
	GameState.slot_index += 1
	GameState.location = ""
	if GameState.slot_index >= slots().size():
		day_over = true
		GameState.time_left = 0
		EventBus.fire("day_ended", {"day": GameState.day, "final": is_final_day()})
		return
	GameState.time_left = units_per_slot()
	EventBus.fire("time_advanced", {"slot_index": GameState.slot_index, "time_left": GameState.time_left,
		"day": GameState.day})


# --- Locations ----------------------------------------------------------------------

func location_ids() -> Array:
	return schedule.get("locations", {}).keys()


func location_name(id: String) -> String:
	return schedule.get("locations", {}).get(id, {}).get("name", id.capitalize())


## Scene backdrop for a location (res:// path), or "" if it has none.
func location_background(id: String) -> String:
	return schedule.get("locations", {}).get(id, {}).get("background", "")


## A location with a "requires" unlock opens once any character has recorded it.
func location_unlocked(id: String) -> bool:
	var needed: String = schedule.get("locations", {}).get(id, {}).get("requires", "")
	if needed == "":
		return true
	for cid in Characters.ids():
		if GameState.char_state(cid).unlocks.has(needed):
			return true
	return false


## "needs Curious (20) with Jessica" for a locked location, else "".
func lock_reason(id: String) -> String:
	var needed: String = schedule.get("locations", {}).get(id, {}).get("requires", "")
	if needed == "" or location_unlocked(id):
		return ""
	for cid in Characters.ids():
		var s: Dictionary = Characters.profile(cid).stage_for_unlock(needed)
		if not s.is_empty():
			return "needs %s (%d) with %s" % [s.label, s.min, Characters.profile(cid).first_name()]
	return "locked"


## Characters scheduled at `location` in the current slot.
func characters_at(location: String) -> Array:
	var slot_id: String = slot().get("id", "")
	var result := []
	for cid in schedule.get("characters", {}):
		if Characters.profile(cid) != null and schedule.characters[cid].get(slot_id) == location:
			result.append(cid)
	return result
