extends Node
## The day: time slots (data/demo_day.json), where each character is in each slot
## (data/schedule.json), time costs (tuning.json -> time) and location locks.

const DEMO_DAY_PATH := "res://data/demo_day.json"
const SCHEDULE_PATH := "res://data/schedule.json"

var demo_day: Dictionary = {}
var schedule: Dictionary = {}
var day_over := false


func _init() -> void:
	demo_day = _load(DEMO_DAY_PATH)
	schedule = _load(SCHEDULE_PATH)


func _load(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func start_day() -> void:
	GameState.reset(demo_day.get("starter_inventory", {}))
	GameState.day = demo_day.get("day", 1)
	for id in Characters.ids():
		Affection.ensure(id)
		GameState.char_state(id).start_affection = Affection.value(id)
	day_over = false
	GameState.slot_index = 0
	GameState.time_left = units_per_slot()
	EventBus.fire("time_advanced", {"slot_index": 0, "time_left": GameState.time_left})


func slots() -> Array:
	return demo_day.get("slots", [])


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
		EventBus.fire("day_ended", {"day": GameState.day})
		return
	GameState.time_left = units_per_slot()
	EventBus.fire("time_advanced", {"slot_index": GameState.slot_index, "time_left": GameState.time_left})


# --- Locations ----------------------------------------------------------------------

func location_ids() -> Array:
	return schedule.get("locations", {}).keys()


func location_name(id: String) -> String:
	return schedule.get("locations", {}).get(id, {}).get("name", id.capitalize())


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
