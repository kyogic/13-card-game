extends Node
## Affection per character (0..profile max). Listens to card and dating events,
## applies the amounts from Config, and records stage unlocks.
## Emits affection_changed and affection_stage_reached on the EventBus.


func _ready() -> void:
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.bomb_played.connect(_on_bomb_played)
	EventBus.two_saved.connect(_on_two_saved)
	EventBus.talk_choice_made.connect(_on_talk_choice)
	EventBus.trivia_answered.connect(_on_trivia_answered)
	EventBus.gift_given.connect(_on_gift_given)


## Records the stages already reached at the current value (e.g. the 0 stage) without
## firing events. Call when a character enters the day.
func ensure(id: String) -> void:
	var st: Dictionary = GameState.char_state(id)
	var profile = Characters.profile(id)
	if profile == null:
		return
	for s in profile.stages():
		if st.affection >= s.min and not st.stages.has(s.label):
			_record_stage(st, s)


func value(id: String) -> int:
	return GameState.char_state(id).affection


func add(id: String, amount: int, reason: String) -> void:
	var profile = Characters.profile(id)
	if profile == null:
		return
	var st: Dictionary = GameState.char_state(id)
	var before: int = st.affection
	var after := clampi(before + amount, 0, profile.affection_max())
	if after == before:
		return
	st.affection = after
	EventBus.fire("affection_changed", {"character_id": id, "delta": after - before, "value": after,
		"reason": reason})
	for s in profile.stages():
		if s.min > before and s.min <= after and not st.stages.has(s.label):
			_record_stage(st, s)
			GameState.log_event("stage", "%s is now: %s" % [profile.first_name(), s.label])
			EventBus.fire("affection_stage_reached", {"character_id": id, "stage": s,
				"unlocks": s.get("unlocks", [])})


## Debug: jump straight to a value (stages crossed on the way up still fire).
func set_value(id: String, target: int) -> void:
	add(id, target - value(id), "debug")


func has_unlock(id: String, key: String) -> bool:
	return GameState.char_state(id).unlocks.has(key)


func _record_stage(st: Dictionary, s: Dictionary) -> void:
	st.stages.append(s.label)
	for key in s.get("unlocks", []):
		if not st.unlocks.has(key):
			st.unlocks.append(key)


# --- Sources ----------------------------------------------------------------------

func _on_match_ended(info: Dictionary) -> void:
	if not GameState.in_date:
		return
	var won: bool = info.get("winner") == "player"
	add(info.opponent_id, Config.int_value("affection.match_won" if won else "affection.match_lost"),
		"won the date match" if won else "played a date match")


func _on_bomb_played(info: Dictionary) -> void:
	if GameState.in_date and info.get("by") == "player":
		add(info.opponent_id, Config.int_value("affection.player_bomb"), "bomb")


func _on_two_saved(info: Dictionary) -> void:
	if GameState.in_date:
		add(info.opponent_id, Config.int_value("affection.two_saved"), "saved a 2")


func _on_talk_choice(info: Dictionary) -> void:
	add(info.character_id, Config.int_value("affection.talk_" + info.quality), "talk")


func _on_trivia_answered(info: Dictionary) -> void:
	add(info.character_id, Config.int_value(
		"affection.trivia_correct" if info.correct else "affection.trivia_wrong"), "trivia")


func _on_gift_given(info: Dictionary) -> void:
	var profile = Characters.profile(info.character_id)
	if profile:
		add(info.character_id, profile.affection_value(info.category), "gift")
