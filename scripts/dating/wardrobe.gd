extends Node
## Outfits (data/outfits.json). Bought with Story Mode money and kept in the player profile
## of the save slot (GameState.profile.wardrobe), so they carry over to new stories in that
## slot. Each girl's first outfit is free.
##
## Wearing: if you've picked an outfit for her, she wears it everywhere (conversations,
## dates, Quickplay). If not, she picks one of your owned outfits for each date.

const OUTFITS_PATH := "res://data/outfits.json"

var outfits := {}              # character id -> [{id, name, path, price}]


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OUTFITS_PATH))
	if parsed is Dictionary:
		for cid in parsed:
			if parsed[cid] is Array and not parsed[cid].is_empty():
				outfits[cid] = parsed[cid]


func _data() -> Dictionary:
	var w: Dictionary = GameState.profile.wardrobe
	for cid in outfits:  # first outfit is always free
		if not w.owned.has(outfits[cid][0].id):
			w.owned.append(outfits[cid][0].id)
	return w


## Drops outfits that aren't in the lineup any more (e.g. after data changes or from old saves).
func clean(data: Dictionary) -> void:
	data.owned = data.get("owned", []).map(func(id): return str(id).replace("abg", "jessica")).filter(
		func(id): return not outfit(id).is_empty())
	var selected: Dictionary = data.get("selected", {})
	for cid in selected.keys():
		if not data.owned.has(selected[cid]):
			selected[cid] = ""
	data.selected = selected


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
	return _data().owned.has(id)


func owned() -> Array:
	return _data().owned


func price(id: String) -> int:
	return int(outfit(id).get("price", 0))


func can_buy(id: String) -> bool:
	return not outfit(id).is_empty() and not is_owned(id) and GameState.money >= price(id)


## Buys with Story Mode money. The outfit is kept in this save slot's profile.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost := price(id)
	GameState.money -= cost
	_data().owned.append(id)
	GameState.log_event("purchase", "Bought the %s outfit for $%d." % [outfit(id).name, cost])
	EventBus.fire("money_changed", {"delta": -cost, "value": GameState.money, "reason": "wardrobe"})
	SaveGame.save_after_profile_change()
	return true


## She'll wear this everywhere until it's taken off.
func wear(id: String) -> void:
	if is_owned(id):
		_data().selected[_owner(id)] = id
		SaveGame.save_after_profile_change()


func take_off(character_id: String) -> void:
	_data().selected[character_id] = ""
	SaveGame.save_after_profile_change()


func worn(character_id: String) -> String:
	return _data().selected.get(character_id, "")


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
