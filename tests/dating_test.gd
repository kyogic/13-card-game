extends SceneTree
## Dating-layer tests. Run: godot --headless --path . --script res://tests/dating_test.gd
## Autoloads are fetched from the tree because test scripts compile before their names exist.


var failures := 0
var bus: Node
var state: Node
var affection: Node
var characters: Node
var config: Node
var events: Array = []


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _record(info: Dictionary, event: String) -> void:
	events.append([event, info])


func _run() -> void:
	bus = root.get_node("EventBus")
	state = root.get_node("GameState")
	affection = root.get_node("Affection")
	characters = root.get_node("Characters")
	config = root.get_node("Config")
	for e in ["affection_changed", "affection_stage_reached"]:
		bus.connect(e, _record.bind(e))
	await _affection_checks()
	await _dialogue_checks()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _affection_checks() -> void:
	check(characters.ids() == ["jessica"], "character registry finds Jessica")
	check(config.int_value("affection.match_won") == 8, "config loaded")
	state.reset()
	affection.ensure("jessica")
	var st: Dictionary = state.char_state("jessica")
	check(st.stages == ["Unimpressed"] and st.unlocks == ["intro_scene"], "starting stage recorded")

	# Card events only count during a date.
	state.in_date = false
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "player"})
	check(affection.value("jessica") == 0, "no affection outside a date")
	state.in_date = true
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "player"})
	check(affection.value("jessica") == 8, "match won +8")
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "opponent"})
	check(affection.value("jessica") == 11, "match lost +3")
	bus.fire("bomb_played", {"opponent_id": "jessica", "by": "player"})
	bus.fire("bomb_played", {"opponent_id": "jessica", "by": "opponent"})
	check(affection.value("jessica") == 13, "player bomb +2, her bomb 0")
	bus.fire("two_saved", {"opponent_id": "jessica"})
	check(affection.value("jessica") == 16, "two_saved +3")
	state.in_date = false

	# Dating-layer sources. 16 + 5 crosses 20 -> Curious.
	events.clear()
	bus.fire("talk_choice_made", {"character_id": "jessica", "quality": "good"})
	var reached := events.filter(func(e): return e[0] == "affection_stage_reached")
	check(reached.size() == 1 and reached[0][1].stage.label == "Curious"
		and st.unlocks.has("boba_date_location"), "crossing 20 reaches Curious and records its unlock")
	bus.fire("talk_choice_made", {"character_id": "jessica", "quality": "bad"})
	check(affection.value("jessica") == 17, "talk good +5, bad -4")
	events.clear()
	bus.fire("trivia_answered", {"character_id": "jessica", "correct": true})
	check(affection.value("jessica") == 24, "trivia correct +7")
	check(events.filter(func(e): return e[0] == "affection_stage_reached").is_empty(),
		"re-crossing a reached stage doesn't fire again")
	bus.fire("trivia_answered", {"character_id": "jessica", "correct": false})
	check(affection.value("jessica") == 21, "trivia wrong -3")
	bus.fire("gift_given", {"character_id": "jessica", "gift_id": "taro_boba", "category": "loved"})
	bus.fire("gift_given", {"character_id": "jessica", "gift_id": "x", "category": "disliked"})
	check(affection.value("jessica") == 31, "gift loved +15, disliked -5")

	# Clamped to 0..100; unlocks stay recorded even if affection drops.
	affection.add("jessica", 500, "test")
	check(affection.value("jessica") == 100 and st.stages.size() == 5, "clamped to 100, all stages")
	affection.add("jessica", -500, "test")
	check(affection.value("jessica") == 0 and st.unlocks.has("final_scene"), "clamped to 0, unlocks kept")

	# Debug set_value fires stage events on the way up.
	state.reset()
	affection.ensure("jessica")
	events.clear()
	affection.set_value("jessica", 72)
	var labels := events.filter(func(e): return e[0] == "affection_stage_reached").map(
		func(e): return e[1].stage.label)
	check(labels == ["Curious", "Into it", "Catching feelings"], "set_value crosses stages: %s" % [labels])

	# Meter shows value + stage and pops up the change.
	var meter = load("res://scripts/ui/affection_meter.gd").new()
	root.add_child(meter)
	meter.set_character("jessica")
	check(meter.label.text == "Affection 72/100  ·  Catching feelings", "meter text: " + meter.label.text)
	affection.add("jessica", 7, "test")
	await process_frame
	var pops: Array = meter.get_children().filter(func(c): return c is Label and c.text == "+7")
	check(pops.size() == 1 and meter.bar.value == 79, "meter pop-up +7")
	meter.queue_free()
	check(state.to_dict().characters.jessica.affection == 79, "state serializes")


# --- Dialogue / conversation / reactions ------------------------------------------

var app: Node
var main: Node
var layer: Node
var convo: Node


## Clicks through whatever the dialogue box is showing.
func _drain() -> void:
	for i in 50:
		await process_frame
		if not convo.dialogue.is_busy():
			return
		convo.dialogue.advance()


func _choices() -> Array:
	return convo.choice_box.get_children().filter(func(c): return not c.is_queued_for_deletion())


func _dialogue_checks() -> void:
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	main = app.card_game
	main.save_path = "user://test_dating_save.cfg"
	main.CPU_DELAY = 60.0  # keep her from playing during scripted checks
	layer = app.dating
	convo = layer.conversation

	bus.fire("demo_day_requested")
	await process_frame
	check(layer.screens.visible and convo.visible, "demo day opens the conversation")
	check(state.inventory.get("taro_boba") == 1 and state.inventory.size() == 4, "starter inventory")
	check(affection.value("jessica") == 0, "day starts at 0 affection")

	# Typewriter: the greeting starts hidden, a click reveals it, another click finishes.
	var db = convo.dialogue
	check(db.is_busy() and db.typing and db.text_label.visible_characters < db.text_label.text.length(),
		"typewriter is still revealing the line")
	db.advance()
	check(not db.typing and db.text_label.visible_characters == -1, "click completes the line")
	check(db.speaker_label.text == "Jessica", "speaker name shown")
	await _drain()
	check(not db.is_busy() and not convo.busy, "greeting done")

	# Talk: lines, then 3 choices; good choice +5 and the exchange is marked seen.
	convo.buttons.talk.pressed.emit()
	await _drain()
	var opts := _choices()
	check(opts.size() == 3, "talk shows 3 choices")
	opts[0].pressed.emit()
	await process_frame
	check(affection.value("jessica") == 5 and state.char_state("jessica").talks_seen == ["boba"], "talk good +5")
	check("lychee" in db.text_label.text, "her reply reveals the trivia answer")
	await _drain()

	# Translation subtitle under Vietnamese lines, toggleable.
	db.play([{"speaker": "Jessica", "text": "Trời ơi.", "translation": "Oh my god."}])
	check(db.subtitle_label.visible and "Oh my god" in db.subtitle_label.text, "subtitle shown")
	convo.subtitles_toggle.button_pressed = false
	check(not db.subtitle_label.visible and not state.settings.subtitles, "subtitles toggle off")
	convo.subtitles_toggle.button_pressed = true
	await _drain()

	# Quiz: pick the right answer -> +7 and recorded.
	convo.buttons.quiz.pressed.emit()
	await process_frame
	var question: String = db.text_label.text
	var q: Dictionary = characters.profile("jessica").trivia().filter(func(t): return t.question == question)[0]
	opts = _choices()
	check(opts.size() == 4, "quiz shows 4 options")
	for b in opts:
		if b.text == q.answer:
			b.pressed.emit()
	await process_frame
	check(affection.value("jessica") == 12 and state.char_state("jessica").trivia_answered == [question],
		"quiz correct +7")
	await _drain()

	# Gift from inventory -> loved +15, her matching line, inventory decremented.
	convo.buttons.gift.pressed.emit()
	await process_frame
	opts = _choices()
	check(opts.size() == 5 and opts.back().text == "Never mind", "gift list from inventory")
	for b in opts:
		if b.text.begins_with("Taro Boba"):
			b.pressed.emit()
	await process_frame
	check(affection.value("jessica") == 27 and state.inventory.taro_boba == 0, "loved gift +15")
	check(db.text_label.text in characters.profile("jessica").data.dialogue.on_gift_loved, "gift reaction line")
	await _drain()

	# Nickname: no "anh" until unlocked (Into it, 45).
	check(not ("anh" in characters.profile("jessica").line("on_game_loss_player",
		state.char_state("jessica").unlocks)), "no 'anh' before it's unlocked")

	# Ask on a date -> the card game starts a match; the dating screens step aside.
	convo.buttons.date.pressed.emit()
	await _drain()
	await process_frame
	check(main.in_date and main.table.visible and main.num_players == 2, "date starts Tiến Lên")
	check(not layer.screens.visible and layer.date_meter.visible and state.in_date, "date HUD shown")
	check(layer.bubble.visible and layer.bubble.last_text in
		characters.profile("jessica").data.dialogue.greeting.map(func(g): return g if g is String else g.text),
		"she greets you in the bubble")

	# Card events during the date: bubble reactions + affection bonuses.
	main._track_play(0, Rules_analyze_quad())
	await process_frame
	check(layer.bubble.last_text in characters.profile("jessica").data.dialogue.on_player_bomb, "bomb reaction")
	check(affection.value("jessica") == 29, "player bomb +2 during date")

	# Win the match -> +8, record, then back to the conversation.
	main.match_wins = [1, 0]
	main.finish_order = [0, 1]
	main.hands[0] = []
	main._end_game()
	check(affection.value("jessica") == 37 and state.match_record.wins == 1, "date match won +8, recorded")
	main._on_again_pressed()
	await process_frame
	check(not state.in_date and layer.screens.visible and convo.visible, "back to the day after the date")
	await _drain()


func Rules_analyze_quad() -> Dictionary:
	var R = load("res://scripts/rules.gd")
	return R.analyze([24, 25, 26, 27])
