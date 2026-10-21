extends RefCounted
## A character profile loaded from data/characters/<id>.json: dialogue, affection
## stages, gifts, trivia and card-AI tuning.

const ANH_UNLOCK := "nickname_anh"

var data: Dictionary = {}


static func load_profile(path: String):
	var profile = new()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		profile.data = parsed
	else:
		push_error("Could not read character profile: %s" % path)
	return profile


func full_name() -> String:
	return data.get("name", "Opponent")


func first_name() -> String:
	return full_name().split(" ")[0]


## A random line for `event`, or "" if the profile has none. She only calls the
## player "anh" once that nickname is unlocked by affection.
func line(event: String, affection: int) -> String:
	var lines: Array = data.get("dialogue", {}).get(event, [])
	if lines.is_empty():
		return ""
	var text: String = lines.pick_random()
	if not is_unlocked(ANH_UNLOCK, affection):
		var re := RegEx.new()
		re.compile(",? anh\\b")
		text = re.sub(text, "", true)
	return text


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


func is_unlocked(key: String, affection: int) -> bool:
	for s in stages():
		if affection >= s.min and s.get("unlocks", []).has(key):
			return true
	return false


## Every gift the profile mentions, as [{id, category}] in loved/liked/disliked order.
func gifts() -> Array:
	var result := []
	var g: Dictionary = data.get("gifts", {})
	for category in ["loved", "liked", "disliked"]:
		for id in g.get(category, []):
			result.append({"id": id, "category": category})
	return result


func gift_category(id: String) -> String:
	for g in gifts():
		if g.id == id:
			return g.category
	return "neutral"


func affection_value(category: String) -> int:
	return data.get("gifts", {}).get("affection_values", {}).get(category, 0)


## Display names for ids whose plain-English capitalisation would lose the Vietnamese.
const DISPLAY_NAMES := {"ca_phe_sua_da": "Cà phê sữa đá", "pho_takeout": "Phở takeout"}


static func pretty(id: String) -> String:
	return DISPLAY_NAMES.get(id, id.replace("_", " ").capitalize())


func trivia() -> Array:
	return data.get("trivia", [])


func card_tuning() -> Dictionary:
	return data.get("card_ai", {}).get("tuning", {})


func signature_powerup() -> String:
	return data.get("card_ai", {}).get("signature_powerup", "")
