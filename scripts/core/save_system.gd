extends Node
## Save slots for Story Mode. Each slot (user://save_slot_N.json) is one player: their
## current story (GameState.to_dict) and their profile (journal + wardrobe), which carries
## over when they start a new story in that slot. The last-used slot is remembered
## (slots.cfg) so the menu Wardrobe and Quickplay know whose outfits to use.

const VERSION := 2
const SLOT_COUNT := 3

var dir := "user://"
var slot := 0                  # active slot (1..SLOT_COUNT), 0 = none
var story_loaded := false      # the active slot's story is in GameState (not just its profile)
## Pre-slot saves, imported into slot 1 once.
var legacy_story_path := "user://dating_save.json"
var legacy_wardrobe_path := "user://wardrobe.cfg"
var legacy_progress_path := "user://save.cfg"


func _ready() -> void:
	startup()


## Imports old saves (once), then loads the last-used slot's profile.
func startup() -> void:
	_migrate_legacy()
	var last := int(_meta().get_value("slots", "last", 0))
	if has_slot(last):
		load_profile(last)
	else:
		slot = 0
		story_loaded = false
		GameState.reset_profile()


func slot_path(n: int) -> String:
	return dir + "save_slot_%d.json" % n


func has_slot(n: int) -> bool:
	return n >= 1 and n <= SLOT_COUNT and FileAccess.file_exists(slot_path(n))


## Starts a new story in slot `n`, keeping that slot's profile (journal, wardrobe).
func new_story(n: int) -> void:
	if has_slot(n):
		load_profile(n)
	else:
		GameState.reset_profile()
		slot = n
	Calendar.start_story()
	story_loaded = true
	save_game()


func load_game(n := slot) -> bool:
	var data := _read(n)
	if not data.has("story"):
		return false
	GameState.from_dict(data.story)
	Calendar.day_over = data.get("day_over", false)
	_apply_profile(data)
	slot = n
	story_loaded = true
	_remember(n)
	EventBus.fire("game_loaded", {"slot": n})
	return true


## Just the player profile (for the menu Wardrobe / Quickplay), not the story.
func load_profile(n: int) -> bool:
	var data := _read(n)
	if data.is_empty():
		return false
	_apply_profile(data)
	slot = n
	story_loaded = false
	_remember(n)
	return true


func save_game() -> bool:
	if slot == 0 or not story_loaded:
		return false
	return _write(slot, {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"story": GameState.to_dict(), "day_over": Calendar.day_over, "profile": GameState.profile})


## Wardrobe changes: a full save during a story, else just the slot's profile.
func save_after_profile_change() -> void:
	if story_loaded:
		save_game()
	elif slot != 0:
		var data := _read(slot)
		data["profile"] = GameState.profile
		_write(slot, data)


func delete_slot(n: int) -> void:
	if has_slot(n):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(n)))
	if slot == n:
		slot = 0
		story_loaded = false
		GameState.reset_profile()
		var meta := _meta()
		meta.set_value("slots", "last", 0)
		meta.save(dir + "slots.cfg")


## For the slot picker: {exists, has_story, day, slot_name, day_over, story_over, saved_at, outfits, facts}.
func slot_info(n: int) -> Dictionary:
	var data := _read(n)
	if data.is_empty():
		return {"exists": false}
	var story: Dictionary = data.get("story", {})
	var day := int(story.get("day", 1))
	var i := int(story.get("slot_index", 0))
	var slots: Array = Calendar.slots()
	var profile: Dictionary = data.get("profile", {})
	var facts := 0
	for cid in profile.get("journal", {}):
		facts += profile.journal[cid].get("known_facts", []).size()
	var day_over: bool = data.get("day_over", false)
	return {"exists": true, "has_story": data.has("story"), "day": day, "slot_name": slots[i].name if i < slots.size() else "",
		"day_over": day_over, "story_over": day_over and day >= Calendar.days(),
		"saved_at": data.get("saved_at", ""), "outfits": profile.get("wardrobe", {}).get("owned", []).size(),
		"facts": facts}


## "Day 2 of 3 · Afternoon · saved 2026-10-21T10:30:00" for the active slot, or "".
func describe(n := slot) -> String:
	var info := slot_info(n)
	if not info.exists:
		return ""
	var when: String = "end of day" if info.day_over else info.slot_name
	return "Day %d of %d · %s · saved %s" % [info.day, Calendar.days(), when, info.saved_at]


func _apply_profile(data: Dictionary) -> void:
	GameState.reset_profile()
	var p: Dictionary = data.get("profile", {})
	if p.get("journal") is Dictionary:
		GameState.profile.journal = p.journal.duplicate(true)
	if p.get("wardrobe") is Dictionary:
		GameState.profile.wardrobe = p.wardrobe.duplicate(true)
	Wardrobe.clean(GameState.profile.wardrobe)


func _read(n: int) -> Dictionary:
	if not has_slot(n):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(slot_path(n)))
	return parsed if parsed is Dictionary else {}


func _write(n: int, data: Dictionary) -> bool:
	var f := FileAccess.open(slot_path(n), FileAccess.WRITE)
	if f == null:
		push_error("Could not save to %s" % slot_path(n))
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_remember(n)
	EventBus.fire("game_saved", {"slot": n})
	return true


func _meta() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(dir + "slots.cfg")
	return cfg


func _remember(n: int) -> void:
	var meta := _meta()
	meta.set_value("slots", "last", n)
	meta.save(dir + "slots.cfg")


## One time: the single save, wardrobe file and coin-era outfits from before slots become slot 1.
func _migrate_legacy() -> void:
	var meta := _meta()
	if meta.get_value("slots", "migrated", false):
		return
	meta.set_value("slots", "migrated", true)
	meta.save(dir + "slots.cfg")
	if range(1, SLOT_COUNT + 1).any(func(n): return has_slot(n)):
		return
	var data := {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"profile": {"journal": {}, "wardrobe": {"owned": [], "selected": {}}}}
	var found := false
	var old = JSON.parse_string(FileAccess.get_file_as_string(legacy_story_path)) \
		if FileAccess.file_exists(legacy_story_path) else null
	if old is Dictionary and old.get("state") is Dictionary:
		found = true
		data["story"] = old.state
		data["day_over"] = old.get("day_over", false)
		for cid in old.state.get("characters", {}):  # journal used to live in the story
			var st: Dictionary = old.state.characters[cid]
			data.profile.journal[cid] = {"met": st.get("met", false), "known_facts": st.get("known_facts", []),
				"gift_notes": st.get("gift_notes", {})}
	var wardrobe := ConfigFile.new()
	if wardrobe.load(legacy_wardrobe_path) == OK:
		found = true
		data.profile.wardrobe = {"owned": wardrobe.get_value("wardrobe", "owned", []),
			"selected": wardrobe.get_value("wardrobe", "selected", {})}
	else:
		var progress := ConfigFile.new()
		if progress.load(legacy_progress_path) == OK and progress.has_section_key("progress", "unlocked"):
			found = true
			data.profile.wardrobe.owned = progress.get_value("progress", "unlocked", [])
	if found:
		Wardrobe.clean(data.profile.wardrobe)
		_write(1, data)
