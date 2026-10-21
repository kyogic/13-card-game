extends Node
## Save/load for the dating day: one save slot in user://dating_save.json holding
## GameState.to_dict() plus whether the day is over. Coins and outfits are saved by the
## card game itself (user://save.cfg).

const VERSION := 1

var path := "user://dating_save.json"


func has_save() -> bool:
	return FileAccess.file_exists(path)


func save_game() -> bool:
	var data := {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"state": GameState.to_dict(), "day_over": Calendar.day_over}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not save to %s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	EventBus.fire("game_saved", {"path": path})
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and parsed.has("state")):
		push_error("Save file is unreadable: %s" % path)
		return false
	GameState.from_dict(parsed.state)
	Calendar.day_over = parsed.get("day_over", false)
	EventBus.fire("game_loaded", {"path": path})
	return true


## "Day 1 · Afternoon · saved 2026-10-21T10:30:00", or "" with no save.
func describe() -> String:
	if not has_save():
		return ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ""
	var slots: Array = Calendar.slots()
	var i := int(parsed.state.get("slot_index", 0))
	var slot_name: String = slots[i].name if i < slots.size() else "end of day"
	return "Day %d · %s · saved %s" % [int(parsed.state.get("day", 1)), slot_name, parsed.get("saved_at", "")]


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
