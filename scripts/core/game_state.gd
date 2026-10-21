extends Node
## State of the dating layer: the current story (several days; to_dict/from_dict) and the
## player profile it belongs to (journal and wardrobe; kept across stories in a save slot).
## Plain data only; SaveGame writes both to the active slot.

var day := 1
var slot_index := 0
var time_left := 0
var location := ""             # where the player is this slot ("" = choosing)
var in_date := false           # a Tiến Lên date is being played
## character id -> {affection, unlocks, stages, trivia_answered (ids), talks_seen (exchange and
## fact ids), soft_facts_seen, start_affection, start_unlocks, met (this story),
## order (pool -> ids shuffled once per story)}
var characters := {}
var inventory := {}            # gift id -> count
var money := 0                 # story money ($), see Economy
var day_start_money := 0       # for the day summary
var shop_stock: Array = []     # item ids for sale today
var match_record := {"wins": 0, "losses": 0}  # whole story
var day_log: Array = []        # [{kind, text}] for the end-of-day summary (cleared each morning)
var settings := {"subtitles": true}
## The player (one per save slot), kept across new stories:
## {"journal": {character id -> {met, known_facts, gift_notes}},
##  "wardrobe": {"owned": [outfit ids], "selected": {character id -> outfit id or ""}}}
var profile := {}


func _init() -> void:
	reset_profile()


func reset_profile() -> void:
	profile = {"journal": {}, "wardrobe": {"owned": [], "selected": {}}}


## What the journal knows about her: {met, known_facts (trivia ids), gift_notes (gift -> reaction)}.
func journal_state(id: String) -> Dictionary:
	if not profile.journal.has(id):
		profile.journal[id] = {"met": false, "known_facts": [], "gift_notes": {}}
	return profile.journal[id]


func reset(starter_inventory: Dictionary = {}) -> void:
	day = 1
	slot_index = 0
	time_left = 0
	location = ""
	in_date = false
	characters = {}
	inventory = starter_inventory.duplicate()
	money = 0
	day_start_money = 0
	shop_stock = []
	match_record = {"wins": 0, "losses": 0}
	day_log = []


func char_state(id: String) -> Dictionary:
	if not characters.has(id):
		characters[id] = {"affection": 0, "unlocks": [], "stages": [], "trivia_answered": [],
			"talks_seen": [], "soft_facts_seen": [], "start_affection": 0, "start_unlocks": [],
			"story_start_affection": 0, "met": false, "order": {}}
	return characters[id]


func log_event(kind: String, text: String) -> void:
	day_log.append({"kind": kind, "text": text})


func to_dict() -> Dictionary:
	return {"day": day, "slot_index": slot_index, "time_left": time_left, "location": location,
		"characters": characters.duplicate(true), "inventory": inventory.duplicate(),
		"money": money, "day_start_money": day_start_money, "shop_stock": shop_stock.duplicate(),
		"match_record": match_record.duplicate(), "day_log": day_log.duplicate(true),
		"settings": settings.duplicate()}


## Restores from to_dict() output. JSON turns every number into a float, so whole
## numbers are converted back to ints here.
func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	slot_index = int(d.get("slot_index", 0))
	time_left = int(d.get("time_left", 0))
	location = d.get("location", "")
	in_date = false
	characters = {}
	for id in d.get("characters", {}):
		var st: Dictionary = char_state(id)  # defaults for keys older saves lack
		for key in d.characters[id]:
			st[key] = d.characters[id][key]
		for key in ["affection", "start_affection", "story_start_affection"]:
			st[key] = int(st[key])
	inventory = {}
	for g in d.get("inventory", {}):
		inventory[g] = int(d.inventory[g])
	money = int(d.get("money", 0))
	day_start_money = int(d.get("day_start_money", money))
	shop_stock = d.get("shop_stock", []).duplicate()
	var record: Dictionary = d.get("match_record", {})
	match_record = {"wins": int(record.get("wins", 0)), "losses": int(record.get("losses", 0))}
	day_log = d.get("day_log", []).duplicate(true)
	settings = d.get("settings", settings).duplicate()


func count_log(kind: String) -> int:
	return day_log.filter(func(e): return e.kind == kind).size()
