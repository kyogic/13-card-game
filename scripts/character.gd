extends RefCounted
## A character profile loaded from data/characters/<id>.json: dialogue, affection
## stages, gifts, trivia and card-AI tuning. Pure data access; no game state.
##
## Dialogue entries may be plain strings or {"text": ..., "translation": ...}.
## Soft facts use "reveal" instead of "text". An entry with "keep_nickname": true keeps
## the player's nickname even before it is unlocked (e.g. a line that teaches it).

## Display names for ids whose plain-English capitalisation would lose the Vietnamese.
const DISPLAY_NAMES := {"ca_phe_sua_da": "Cà phê sữa đá", "pho_takeout": "Phở takeout"}

var data: Dictionary = {}


static func load_profile(path: String):
	var profile = new()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		profile.data = parsed
	else:
		push_error("Could not read character profile: %s" % path)
	return profile


func id() -> String:
	return data.get("id", "")


func full_name() -> String:
	return data.get("name", "Opponent")


func first_name() -> String:
	return full_name().split(" ")[0]


func portrait() -> String:
	return data.get("portrait", "")


## What the card game needs to play against this character.
func to_opponent() -> Dictionary:
	return {"id": id(), "name": first_name(), "full_name": full_name(), "portrait": portrait(),
		"tuning": card_tuning(), "signature_powerup": signature_powerup()}


func has_lines(event: String) -> bool:
	return not data.get("dialogue", {}).get(event, []).is_empty()


## A random line for `event` as {"text", "translation"}, or {} if there is none.
## The player's nickname (e.g. "anh") is removed until its unlock has been earned.
func line_entry(event: String, unlocks: Array = []) -> Dictionary:
	var lines: Array = data.get("dialogue", {}).get(event, [])
	if lines.is_empty():
		return {}
	return normalize(lines.pick_random(), unlocks)


## Turns a string or {text, translation} entry into a dictionary, applying the nickname rule.
func normalize(entry, unlocks: Array = []) -> Dictionary:
	var result: Dictionary = entry.duplicate() if entry is Dictionary else {"text": str(entry)}
	if result.has("reveal") and not result.has("text"):
		result["text"] = result.reveal
	var nick: Dictionary = data.get("nickname_for_player", {})
	if not nick.is_empty() and not unlocks.has(nick.get("unlock", "")) and not result.get("keep_nickname", false):
		var re := RegEx.new()
		re.compile(",? %s\\b" % nick.word)
		for key in ["text", "translation"]:
			if result.has(key):
				result[key] = re.sub(result[key], "", true)
	return result


## Text-only convenience wrapper around line_entry().
func line(event: String, unlocks: Array = []) -> String:
	return line_entry(event, unlocks).get("text", "")


func affection_max() -> int:
	return data.get("affection", {}).get("max", 100)


func stages() -> Array:
	return data.get("affection", {}).get("stages", [])


func stage(affection: int) -> Dictionary:
	var current := {}
	for s in stages():
		if affection >= s.min:
			current = s
	return current


func next_stage(affection: int) -> Dictionary:
	for s in stages():
		if affection < s.min:
			return s
	return {}


## The stage whose unlocks include `key`, or {}.
func stage_for_unlock(key: String) -> Dictionary:
	for s in stages():
		if s.get("unlocks", []).has(key):
			return s
	return {}


## Every gift the profile mentions, as [{id, category}] in loved/liked/disliked order.
func gifts() -> Array:
	var result := []
	var g: Dictionary = data.get("gifts", {})
	for category in ["loved", "liked", "disliked"]:
		for gift_id in g.get(category, []):
			result.append({"id": gift_id, "category": category})
	return result


func gift_category(gift_id: String) -> String:
	for g in gifts():
		if g.id == gift_id:
			return g.category
	return "neutral"


func affection_value(category: String) -> int:
	return data.get("gifts", {}).get("affection_values", {}).get(category, 0)


static func pretty(gift_id: String) -> String:
	return DISPLAY_NAMES.get(gift_id, gift_id.replace("_", " ").capitalize())


func trivia() -> Array:
	return data.get("trivia", [])


## Stable id for a trivia question (older profiles have no "id"; fall back to the text).
static func trivia_id(q: Dictionary) -> String:
	return q.get("id", q.get("question", ""))


## Trivia she'll ask at this affection (questions can have "min_affection").
func trivia_available(affection: int) -> Array:
	return trivia().filter(func(q): return affection >= q.get("min_affection", 0))


## Personal things she only shares past an affection threshold: [{id, min_affection, reveal}].
func soft_facts() -> Array:
	return data.get("soft_facts", [])


func date_locations() -> Array:
	return data.get("date_locations", [])


func card_tuning() -> Dictionary:
	return data.get("card_ai", {}).get("tuning", {})


func signature_powerup() -> String:
	return data.get("card_ai", {}).get("signature_powerup", "")
