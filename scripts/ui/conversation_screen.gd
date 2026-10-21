extends Control
## HuniePop-style conversation with one character: Talk, Give gift, Ask on a date, Leave.
## Talk is the whole conversation: small talk, things she opens up about, and now and then
## a question about herself (her trivia). Content comes from the character JSON and
## data/talk/<id>.json.
##
## Time is handled by whoever opens the screen: it sets `can_afford` and listens to
## `action_taken(kind)` ("talk", "quiz", "gift"). A date is requested on the EventBus.

signal action_taken(kind: String)
signal left
signal journal_pressed

const AffectionMeter := preload("res://scripts/ui/affection_meter.gd")
const Character := preload("res://scripts/character.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")

var can_afford: Callable = func(_kind): return true
var character_id := ""
var location_id := ""
var profile

var portrait: TextureRect
var title_label: Label
var status_label: Label
var meter
var subtitles_toggle: CheckButton
var buttons := {}              # action -> Button
var choice_box: VBoxContainer
var dialogue
var busy := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.09, 0.18)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_offsets(portrait, 10, 470, 10, -10)
	add_child(portrait)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_offsets(col, 490, -24, 20, -220)
	add_child(col)
	var top := HBoxContainer.new()
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	subtitles_toggle = CheckButton.new()
	subtitles_toggle.text = "English subtitles"
	subtitles_toggle.toggled.connect(_on_subtitles_toggled)
	top.add_child(subtitles_toggle)
	var journal_button := Button.new()
	journal_button.text = "Journal"
	journal_button.add_theme_font_size_override("font_size", 16)
	journal_button.pressed.connect(func(): journal_pressed.emit())
	top.add_child(journal_button)
	col.add_child(top)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	col.add_child(status_label)
	meter = AffectionMeter.new()
	col.add_child(meter)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	for a in [["talk", "Talk"], ["gift", "Give gift"], ["date", "Ask on a date"], ["leave", "Leave"]]:
		var b := Button.new()
		b.text = a[1]
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(Callable(self, "_on_" + a[0]))
		actions.add_child(b)
		buttons[a[0]] = b
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 6)
	col.add_child(choice_box)

	dialogue = DialogueBox.new()
	dialogue.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN  # long lines grow upwards, not off-screen
	_offsets(dialogue, 490, -24, -205, -16)
	add_child(dialogue)


func _offsets(c: Control, l: float, r: float, t: float, b: float) -> void:
	c.offset_left = l
	c.offset_right = r
	c.offset_top = t
	c.offset_bottom = b


## Opens the screen for `id` at `location`. `location_name` is just for display.
func open(id: String, location: String, location_name: String) -> void:
	character_id = id
	location_id = location
	profile = Characters.profile(id)
	title_label.text = "%s  ·  %s" % [profile.first_name(), location_name]
	var look: String = Wardrobe.look_path(id)
	portrait.texture = load(look) if look != "" else null
	subtitles_toggle.set_pressed_no_signal(GameState.settings.get("subtitles", true))
	meter.set_character(id)
	_clear_choices()
	visible = true
	# You've only just met the first time; after that it's a "hello again".
	var first_time: bool = not GameState.char_state(id).met
	EventBus.fire("conversation_opened", {"character_id": id, "location": location})
	if first_time and profile.has_lines("first_meeting"):
		_say_event("first_meeting")
	elif profile.has_lines("hello"):
		_say_event("hello")
	else:
		_say_event("greeting")


func set_status(text: String) -> void:
	status_label.text = text
	refresh()


func refresh() -> void:
	if profile == null:
		return
	var talk_left := _next_talk() != null or not _unanswered_trivia().is_empty()
	var gifts_left := GameState.inventory.values().any(func(n): return n > 0)
	var can_date: bool = profile.date_locations().has(location_id)
	_set_button("talk", "Talk", talk_left, "nothing new")
	_set_button("gift", "Give gift", gifts_left, "no gifts")
	_set_button("date", "Ask on a date", can_date, "not a date spot")
	buttons.leave.disabled = busy


func _set_button(kind: String, text: String, available: bool, why_not: String) -> void:
	var b: Button = buttons[kind]
	var affordable: bool = kind == "date" or can_afford.call(kind)
	b.disabled = busy or not available or not affordable
	b.text = text if available and affordable else "%s (%s)" % [text, why_not if not available else "no time"]


# --- Lines ------------------------------------------------------------------------

## Converts talk-file / profile entries into dialogue-box lines with display names.
func _lines(entries: Array) -> Array:
	var unlocks: Array = GameState.char_state(character_id).unlocks
	var out := []
	for e in entries:
		var line: Dictionary = profile.normalize(e, unlocks)
		var speaker: String = e.get("speaker", character_id) if e is Dictionary else character_id
		line["speaker"] = _speaker_name(speaker)
		out.append(line)
	return out


func _speaker_name(speaker: String) -> String:
	if speaker == "player":
		return "You"
	if speaker == "narrator" or speaker == "":
		return ""
	var p = Characters.profile(speaker)
	return p.first_name() if p else speaker


## Plays a random profile line for `event`, then calls `then`.
func _say_event(event: String, then := Callable()) -> void:
	var entry: Dictionary = profile.line_entry(event, GameState.char_state(character_id).unlocks)
	if entry.is_empty():
		if then.is_valid():
			then.call()
		return
	entry["speaker"] = character_id
	_play(_lines([entry]), then)


func _narrate(text: String, then := Callable()) -> void:
	_play([{"speaker": "", "text": text}], then)


func _play(lines: Array, then := Callable()) -> void:
	busy = true
	refresh()
	dialogue.play(lines)
	await dialogue.finished
	busy = false
	refresh()
	if then.is_valid():
		then.call()


func _clear_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()


func _show_choices(options: Array, on_pick: Callable) -> void:
	_clear_choices()
	busy = true
	refresh()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			_clear_choices()
			busy = false
			on_pick.call(i))
		choice_box.add_child(b)


# --- Actions ----------------------------------------------------------------------

## What the next Talk will be: a soft fact she's now ready to share (these come first),
## then the next small-talk exchange, then a one-line fact. Returns {kind, data} or null.
func _next_talk():
	var st: Dictionary = GameState.char_state(character_id)
	for f in _ordered("soft_facts", profile.soft_facts()):
		if st.affection >= f.get("min_affection", 0) and not st.soft_facts_seen.has(f.id):
			return {"kind": "soft_fact", "data": f}
	for ex in _ordered("exchanges", Characters.talk(character_id)):
		if not st.talks_seen.has(ex.id):
			return {"kind": "exchange", "data": ex}
	for f in _ordered("facts", Characters.fact_lines(character_id)):
		if not st.talks_seen.has(f.id):
			return {"kind": "fact", "data": f}
	return null


## `items` (each with an id) in this story's shuffled order for `pool`, so every playthrough
## brings things up in a different order. The order is saved with the story, so it holds
## across save/load; anything new in the data is shuffled in.
func _ordered(pool: String, items: Array) -> Array:
	var orders: Dictionary = GameState.char_state(character_id).order
	var ids: Array = items.map(func(it): return Character.trivia_id(it))
	var order: Array = orders.get(pool, []).filter(func(id): return ids.has(id))
	var fresh: Array = ids.filter(func(id): return not order.has(id))
	fresh.shuffle()
	order.append_array(fresh)
	orders[pool] = order
	var sorted := items.duplicate()
	sorted.sort_custom(func(a, b): return order.find(Character.trivia_id(a)) < order.find(Character.trivia_id(b)))
	return sorted


## Talk: what she's ready to open up about comes first; otherwise she sometimes turns it
## round and asks you something about herself (never twice in a row), else small talk.
func _on_talk() -> void:
	var next = _next_talk()
	var st: Dictionary = GameState.char_state(character_id)
	var can_ask := not _unanswered_trivia().is_empty()
	if next == null and not can_ask:
		_say_event("on_talk_done")
		return
	if can_ask and (next == null or next.kind != "soft_fact" and _wants_to_ask()):
		st["asked_last"] = true
		_ask_question()
		return
	st["asked_last"] = false
	if next.kind == "soft_fact":
		var f: Dictionary = next.data
		st.soft_facts_seen.append(f.id)
		GameState.log_event("talk", "%s opened up about %s." % [profile.first_name(), f.id.replace("_", " ")])
		_learned([f.id], "talk")
		var reveal: Dictionary = f.duplicate()
		reveal["speaker"] = character_id
		_play(_lines([reveal]), func(): _say_event("on_soft_fact_revealed", func(): action_taken.emit("talk")))
		return
	if next.kind == "fact":
		var fact: Dictionary = next.data
		st.talks_seen.append(fact.id)
		GameState.log_event("talk", "%s mentioned her %s." % [profile.first_name(), fact.id.replace("_", " ")])
		_learned(fact.get("teaches", []), "talk")
		_play(_lines(fact.lines), func(): action_taken.emit("talk"))
		return
	var ex: Dictionary = next.data
	_play(_lines(ex.lines), func():
		dialogue.show_static(profile.first_name(), "...", "")
		_show_choices(ex.choices.map(func(c): return c.text), func(i):
			var choice: Dictionary = ex.choices[i]
			GameState.char_state(character_id).talks_seen.append(ex.id)
			GameState.log_event("talk", "Talked with %s about %s (%s answer)." % [profile.first_name(),
				ex.id.replace("_", " "), choice.quality])
			EventBus.fire("talk_choice_made", {"character_id": character_id, "quality": choice.quality,
				"exchange": ex.id})
			_learned(ex.get("teaches", []), "talk")
			_play(_lines(choice.reply), func(): action_taken.emit("talk"))))


## Questions she'll still ask: not answered yet, and within her current affection gate.
## Tells the journal (and anyone else) what you just found out about her.
func _learned(facts: Array, source: String) -> void:
	EventBus.fire("fact_learned", {"character_id": character_id, "facts": facts, "source": source})


func _unanswered_trivia() -> Array:
	var st: Dictionary = GameState.char_state(character_id)
	return profile.trivia_available(st.affection).filter(
		func(q): return not st.trivia_answered.has(Character.trivia_id(q)))


## Whether this Talk is her asking you a question (conversation.question_chance in tuning).
func _wants_to_ask() -> bool:
	if GameState.char_state(character_id).get("asked_last", false):
		return false
	return randf() < float(Config.value("conversation.question_chance", 0.35))


## She asks one of her trivia questions, lead-in line first if she has one.
func _ask_question() -> void:
	var pool := _ordered("quiz", _unanswered_trivia())
	if pool.is_empty():
		return
	var q: Dictionary = pool[0]  # next in this story's shuffled order (within her affection gate)
	if profile.has_lines("question_lead_in"):
		_say_event("question_lead_in", _show_question.bind(q))
	else:
		_show_question(q)


func _show_question(q: Dictionary) -> void:
	var options: Array = q.wrong.duplicate()
	options.append(q.answer)
	options.shuffle()
	dialogue.show_static(profile.first_name(), q.question)
	_show_choices(options, func(i):
		var correct: bool = options[i] == q.answer
		GameState.char_state(character_id).trivia_answered.append(Character.trivia_id(q))
		GameState.log_event("trivia_correct" if correct else "trivia_wrong", "%s \"%s\" — %s." % [
			"Got" if correct else "Missed", q.question, "right" if correct else "wrong"])
		EventBus.fire("trivia_answered", {"character_id": character_id, "question": Character.trivia_id(q),
			"correct": correct})
		if correct:
			_learned([Character.trivia_id(q)], "quiz")
			_say_event("on_trivia_correct", func(): action_taken.emit("quiz"))
		else:
			_say_event("on_trivia_wrong", func(): action_taken.emit("quiz")))  # no answer: learn it by talking


func _on_gift() -> void:
	var ids := GameState.inventory.keys().filter(func(g): return GameState.inventory[g] > 0)
	var labels: Array = ids.map(func(g): return "%s  ×%d" % [Character.pretty(g), GameState.inventory[g]])
	labels.append("Never mind")
	dialogue.show_static("", "Which gift?")
	_show_choices(labels, func(i):
		if i >= ids.size():
			dialogue.show_static("", "")
			refresh()
			return
		give_gift(ids[i]))


## Gives `gift_id` from the inventory and plays her reaction.
func give_gift(gift_id: String) -> void:
	GameState.inventory[gift_id] -= 1
	var category: String = profile.gift_category(gift_id)
	GameState.log_event("gift", "Gave %s a %s (%s)." % [profile.first_name(), Character.pretty(gift_id), category])
	EventBus.fire("gift_given", {"character_id": character_id, "gift_id": gift_id, "category": category})
	var done := func(): action_taken.emit("gift")
	if profile.has_lines("on_gift_" + category):
		_say_event("on_gift_" + category, done)
	else:
		_narrate("She takes the %s." % Character.pretty(gift_id).to_lower(), done)


func _on_date() -> void:
	_say_event("on_date_ask", func():
		visible = false
		var opponent: Dictionary = profile.to_opponent()
		opponent["portrait"] = Wardrobe.match_path(character_id)  # her outfit for this date
		EventBus.fire("date_requested", {"character_id": character_id, "location": location_id,
			"opponent": opponent}))


func _on_leave() -> void:
	visible = false
	left.emit()


func _on_subtitles_toggled(on: bool) -> void:
	GameState.settings.subtitles = on
	dialogue.refresh_subtitle()
