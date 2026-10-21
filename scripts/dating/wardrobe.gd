extends Node
## Outfit collection (data/outfits.json). Outfits are bought with Story Mode money and kept
## forever (user://wardrobe.cfg), across new stories. Each girl's first outfit is free.
##
## Wearing: if you've picked an outfit for her, she wears it everywhere (conversations,
## dates, Quickplay). If not, she picks one of your owned outfits for each date.

const OUTFITS_PATH := "res://data/outfits.json"
var path := "user://wardrobe.cfg"
var legacy_path := "user://save.cfg"  # outfits unlocked with the old coins carry over
var outfits := {}              # character id -> [{id, name, path, price}]
var owned: Array = []
var selected := {}             # character id -> outfit id she always wears ("" = her choice)


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OUTFITS_PATH))
	if parsed is Dictionary:
		for cid in parsed:
			if parsed[cid] is Array and not parsed[cid].is_empty():
				outfits[cid] = parsed[cid]
	load_collection()


func load_collection() -> void:
	owned = []
	selected = {}
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		owned = cfg.get_value("wardrobe", "owned", [])
		selected = cfg.get_value("wardrobe", "selected", {})
	else:
		var legacy := ConfigFile.new()
		if legacy.load(legacy_path) == OK:
			owned = legacy.get_value("progress", "unlocked", []).map(func(id): return str(id).replace("abg", "jessica"))
	owned = owned.filter(func(id): return not outfit(id).is_empty())
	for cid in outfits:
		if not owned.has(outfits[cid][0].id):
			owned.append(outfits[cid][0].id)  # first outfit is free
		if not owned.has(selected.get(cid, "")):
			selected[cid] = ""


func save_collection() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wardrobe", "owned", owned)
	cfg.set_value("wardrobe", "selected", selected)
	cfg.save(path)


func outfits_for(character_id: String) -> Array:
	return outfits.get(character_id, [])


func outfit(id: String) -> Dictionary:
	for cid in outfits:
		for o in outfits[cid]:
			if o.id == id:
				return o
	return {}


func _owner(id: String) -> String:
	for cid in outfits:
		if outfits[cid].any(func(o): return o.id == id):
			return cid
	return ""


func is_owned(id: String) -> bool:
	return owned.has(id)


func price(id: String) -> int:
	return int(outfit(id).get("price", 0))


func can_buy(id: String) -> bool:
	return not outfit(id).is_empty() and not is_owned(id) and GameState.money >= price(id)


## Buys with Story Mode money. The outfit is kept forever.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost := price(id)
	GameState.money -= cost
	owned.append(id)
	save_collection()
	GameState.log_event("purchase", "Bought the %s outfit for $%d." % [outfit(id).name, cost])
	EventBus.fire("money_changed", {"delta": -cost, "value": GameState.money, "reason": "wardrobe"})
	return true


## She'll wear this everywhere until it's taken off.
func wear(id: String) -> void:
	if is_owned(id):
		selected[_owner(id)] = id
		save_collection()


func take_off(character_id: String) -> void:
	selected[character_id] = ""
	save_collection()


func worn(character_id: String) -> String:
	return selected.get(character_id, "")


## Portrait for conversations: her worn outfit, else her first (default) outfit.
func look_path(character_id: String) -> String:
	var id := worn(character_id)
	if id == "" and not outfits_for(character_id).is_empty():
		id = outfits_for(character_id)[0].id
	return outfit(id).get("path", _profile_portrait(character_id))


## Portrait for a match: her worn outfit, else a random owned one (kept for that match).
func match_path(character_id: String) -> String:
	var id := worn(character_id)
	if id == "":
		var mine: Array = outfits_for(character_id).filter(func(o): return is_owned(o.id))
		id = mine.pick_random().id if not mine.is_empty() else ""
	return outfit(id).get("path", _profile_portrait(character_id))


func _profile_portrait(character_id: String) -> String:
	var profile = Characters.profile(character_id)
	return profile.portrait() if profile else ""
