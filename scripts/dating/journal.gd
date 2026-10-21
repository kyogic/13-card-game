extends Node
## The player's journal: what you've learned about each girl. Records facts as they come
## up in conversation (fact_learned), her reaction to each gift, and whether you've met.
## It belongs to the player profile (GameState.profile), so it carries over to new stories.
## Fact labels come from her trivia: an optional "journal_label", else the trivia id.


func _ready() -> void:
	EventBus.conversation_opened.connect(func(i):
		GameState.char_state(i.character_id).met = true  # this story (greetings)
		GameState.journal_state(i.character_id).met = true)
	EventBus.fact_learned.connect(_on_fact_learned)
	EventBus.gift_given.connect(_on_gift_given)


func _on_fact_learned(info: Dictionary) -> void:
	var known: Array = GameState.journal_state(info.character_id).known_facts
	for f in info.get("facts", []):
		if not known.has(f):
			known.append(f)


func _on_gift_given(info: Dictionary) -> void:
	GameState.journal_state(info.character_id).gift_notes[info.gift_id] = info.category


## Known facts in her trivia order: [{id, label, text}].
func entries(id: String) -> Array:
	var profile = Characters.profile(id)
	if profile == null:
		return []
	var known: Array = GameState.journal_state(id).known_facts
	var result := []
	for q in profile.trivia():
		var qid: String = profile.trivia_id(q)
		if known.has(qid):
			result.append({"id": qid, "label": q.get("journal_label", _sentence_case(qid)), "text": q.answer})
	return result


## "boba_order" -> "Boba order".
static func _sentence_case(id: String) -> String:
	var words := id.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


func total(id: String) -> int:
	var profile = Characters.profile(id)
	return profile.trivia().size() if profile else 0


## Gift ids she's reacted to, grouped: {"loved": [...], "liked": [...], ...}.
func gift_notes(id: String) -> Dictionary:
	var grouped := {}
	var notes: Dictionary = GameState.journal_state(id).gift_notes
	for g in notes:
		if not grouped.has(notes[g]):
			grouped[notes[g]] = []
		grouped[notes[g]].append(g)
	return grouped
