extends Node
## In-memory state of the dating layer for the current day. Plain data only, so
## save/load can later be added with to_dict() / from_dict(). Not saved yet.

var day := 1
var slot_index := 0
var time_left := 0
var location := ""             # where the player is this slot ("" = choosing)
var in_date := false           # a Tiến Lên date is being played
## character id -> {affection, unlocks, stages, trivia_answered, talks_seen, start_affection}
var characters := {}
var inventory := {}            # gift id -> count
var match_record := {"wins": 0, "losses": 0}
var day_log: Array = []        # [{kind, text}] for the end-of-day summary
var settings := {"subtitles": true}


func reset(starter_inventory: Dictionary = {}) -> void:
	day = 1
	slot_index = 0
	time_left = 0
	location = ""
	in_date = false
	characters = {}
	inventory = starter_inventory.duplicate()
	match_record = {"wins": 0, "losses": 0}
	day_log = []


func char_state(id: String) -> Dictionary:
	if not characters.has(id):
		characters[id] = {"affection": 0, "unlocks": [], "stages": [], "trivia_answered": [],
			"talks_seen": [], "start_affection": 0}
	return characters[id]


func log_event(kind: String, text: String) -> void:
	day_log.append({"kind": kind, "text": text})


func to_dict() -> Dictionary:
	return {"day": day, "slot_index": slot_index, "time_left": time_left, "location": location,
		"characters": characters.duplicate(true), "inventory": inventory.duplicate(),
		"match_record": match_record.duplicate(), "day_log": day_log.duplicate(true),
		"settings": settings.duplicate()}


func from_dict(d: Dictionary) -> void:
	day = d.get("day", 1)
	slot_index = d.get("slot_index", 0)
	time_left = d.get("time_left", 0)
	location = d.get("location", "")
	characters = d.get("characters", {}).duplicate(true)
	inventory = d.get("inventory", {}).duplicate()
	match_record = d.get("match_record", {"wins": 0, "losses": 0}).duplicate()
	day_log = d.get("day_log", []).duplicate(true)
	settings = d.get("settings", settings).duplicate()
