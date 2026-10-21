extends SceneTree
## Dating-layer tests. Run: godot --headless --path . --script res://tests/dating_test.gd
## Autoloads are fetched from the tree because test scripts compile before their names exist.


var failures := 0
var checks := 0
var bus: Node
var state: Node
var affection: Node
var characters: Node
var config: Node
var events: Array = []


func _init() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)


const TEST_DIR := "user://test_slots/"


## Points SaveGame at an empty test directory (no slots, no legacy files) and starts up.
func _use_test_saves() -> void:
	var saver: Node = root.get_node("SaveGame")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR + f))
	saver.dir = TEST_DIR
	saver.legacy_story_path = TEST_DIR + "legacy_dating_save.json"
	saver.legacy_wardrobe_path = TEST_DIR + "legacy_wardrobe.cfg"
	saver.legacy_progress_path = TEST_DIR + "legacy_save.cfg"
	saver.startup()


func _record(info: Dictionary, event: String) -> void:
	events.append([event, info])


func _run() -> void:
	bus = root.get_node("EventBus")
	_use_test_saves()  # never touch the real save slots
	state = root.get_node("GameState")
	affection = root.get_node("Affection")
	characters = root.get_node("Characters")
	config = root.get_node("Config")
	config.data.conversation.question_chance = 0.0  # Talk is small talk unless a check asks for a question
	config.data.conversation.compatibility_chance = 0.0
	for e in ["affection_changed", "affection_stage_reached"]:
		bus.connect(e, _record.bind(e))
	await _affection_checks()
	await _dialogue_checks()
	print("CHECKS: %d  FAILURES: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _affection_checks() -> void:
	var ids: Array = characters.ids()
	ids.sort()
	check(ids == ["arisa", "jessica"], "character registry finds both girls: %s" % [ids])
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


var first_exchange: Dictionary = {}


func _texts(entries: Array) -> Array:
	return entries.map(func(e): return e.text if e is Dictionary else e)


## Every story shuffles what she talks about and asks; the order holds across save/load.
func _order_checks() -> void:
	var orders := []
	for i in 4:
		bus.fire("new_story_requested")
		await process_frame
		layer.calendar.location_buttons.pho_spot.pressed.emit()
		await _drain()
		check(convo.dialogue.text_label.text in _texts(characters.profile("jessica").data.dialogue.first_meeting)
			or not convo.dialogue.is_busy(), "new story: she introduces herself again")
		convo._ordered("exchanges", characters.talk("jessica"))
		convo._ordered("facts", characters.fact_lines("jessica"))
		convo._ordered("soft_facts", characters.profile("jessica").soft_facts())
		convo._ordered("quiz", convo._unanswered_trivia())
		var o: Dictionary = state.char_state("jessica").order
		orders.append([o.exchanges.duplicate(), o.facts.duplicate(), o.quiz.duplicate(), o.soft_facts.duplicate()])
		check(o.exchanges.size() == characters.talk("jessica").size() and o.quiz.size() == 18
			and o.soft_facts.size() == characters.profile("jessica").soft_facts().size(), "every pool is ordered")
	check(orders.map(func(x): return x[0]).any(func(x): return x != orders[0][0])
		and orders.map(func(x): return x[2]).any(func(x): return x != orders[0][2]), "order differs between stories")
	# Same story: the order survives a save/load, and the quiz only ever offers gated questions in order.
	var saved: Array = state.char_state("jessica").order.quiz.duplicate()
	root.get_node("SaveGame").save_game()
	state.char_state("jessica").order = {}
	root.get_node("SaveGame").load_game()
	check(state.char_state("jessica").order.quiz == saved, "order is saved with the story")
	var asked: Dictionary = convo._ordered("quiz", convo._unanswered_trivia())[0]
	check(asked.id == saved[0] and asked.get("min_affection", 0) <= affection.value("jessica"),
		"the quiz asks the next available question in this story's order")
	# Second conversation in the same story: "hello again", not an introduction.
	convo._on_leave()
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await process_frame
	check(convo.dialogue.text_label.text in _texts(characters.profile("jessica").data.dialogue.hello),
		"after the first meeting she says hello again: " + convo.dialogue.text_label.text)
	await _drain()
	layer.hide_all()


# --- Journal ------------------------------------------------------------------------

func _journal_checks(quizzed: Dictionary) -> void:
	var journal: Node = root.get_node("Journal")
	var st: Dictionary = state.journal_state("jessica")
	check(st.met and not state.journal_state("arisa").met, "journal knows who you've met")
	var taught: String = first_exchange.teaches[0]
	var taught_q: Dictionary = characters.profile("jessica").trivia().filter(func(t): return t.id == taught)[0]
	check(st.known_facts.has(taught) and st.known_facts.has(quizzed.id),
		"talk and right quiz answers are recorded: %s" % [st.known_facts])
	var entries: Array = journal.entries("jessica")
	check(entries.size() == st.known_facts.size() and entries.any(
		func(e): return e.id == taught and e.text == taught_q.answer), "journal entries")
	check(journal.gift_notes("jessica") == {"loved": ["taro_boba"]}, "gift reactions noted")
	convo.journal_pressed.emit()
	var page = layer.journal
	check(page.visible and page.character_id == "jessica" and taught_q.answer in page.facts_label.text
		and ("of %d" % journal.total("jessica")) in page.progress_label.text and "Taro Boba" in page.gifts_label.text,
		"journal page from the conversation")
	page.show_page("arisa")
	check(page.facts_label.text == "You haven't met her yet.", "unmet girl's page")
	page.get_child(1).find_children("*", "Button", true, false).filter(func(b): return b.text == "Close")[0].pressed.emit()
	check(not page.visible and convo.visible, "closing the journal returns to the conversation")


# --- Dialogue / conversation / reactions ------------------------------------------

var app: Node
var main: Node
var layer: Node
var convo: Node


## How Talk mixes small talk and questions (decided without playing anything out).
func _question_mix_checks() -> void:
	var st: Dictionary = state.char_state("jessica")
	config.data.conversation.question_chance = 0.35
	var asks := 0
	for i in 200:
		st.erase("asked_last")
		if convo._wants_to_ask():
			asks += 1
	check(asks > 30 and asks < 120, "she asks a question about a third of the time (%d/200)" % asks)
	config.data.conversation.question_chance = 1.0
	st["asked_last"] = true
	check(not convo._wants_to_ask(), "never two questions in a row")
	config.data.conversation.question_chance = 0.0
	st.erase("asked_last")


## Clicks through whatever the dialogue box is showing.
func _drain() -> void:
	for i in 50:
		await process_frame
		if not convo.dialogue.is_busy():
			return
		convo.dialogue.advance()


## Talk, with her asking a question this time; returns once the question is on screen.
func _talk_question() -> void:
	config.data.conversation.question_chance = 1.0
	state.char_state(convo.character_id).erase("asked_last")
	convo.buttons.talk.pressed.emit()
	config.data.conversation.question_chance = 0.0
	await _drain()


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

	cal = root.get_node("Calendar")
	bus.fire("new_story_requested")
	await process_frame
	check(layer.screens.visible and layer.calendar.visible and not convo.visible, "demo day opens the calendar")
	check(cal.slot_name() == "Morning" and state.time_left == 3, "morning, 3 time units")
	check(state.inventory.get("taro_boba") == 1 and state.inventory.get("mango_sticky_rice") == 1
		and state.inventory.size() == 6, "starter inventory has gifts for both")
	check(affection.value("jessica") == 0, "day starts at 0 affection")
	var open: Array = cal.location_ids().filter(func(l): return cal.location_unlocked(l))
	open.sort()
	check(open == ["muay_thai_gym", "night_owl_mart", "pho_spot"], "open at 0 affection: %s" % [open])
	check(layer.calendar.location_buttons.boba_shop.disabled
		and "Curious (20)" in layer.calendar.location_buttons.boba_shop.text, "locked location explains why")
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await process_frame
	check(convo.visible and convo.location_id == "pho_spot", "she's at the phở spot in the morning")

	# Typewriter: the greeting starts hidden, a click reveals it, another click finishes.
	var db = convo.dialogue
	check(db.is_busy() and db.typing and db.text_label.visible_characters < db.text_label.text.length(),
		"typewriter is still revealing the line")
	db.advance()
	check(not db.typing and db.text_label.visible_characters == -1, "click completes the line")
	check(db.speaker_label.text == "Jessica", "speaker name shown")
	check(db.text_label.text in _texts(characters.profile("jessica").data.dialogue.first_meeting),
		"first conversation: she introduces herself")
	await _drain()
	check(not db.is_busy() and not convo.busy, "greeting done")

	# Talk: lines, then 3 choices; good choice +5 and the exchange is marked seen.
	convo.buttons.talk.pressed.emit()
	await _drain()
	var opts := _choices()
	check(opts.size() == 3, "talk shows 3 choices")
	opts[0].pressed.emit()
	await process_frame
	var first_id: String = state.char_state("jessica").order.exchanges[0]
	first_exchange = characters.talk("jessica").filter(func(e): return e.id == first_id)[0]
	check(affection.value("jessica") == 5 and state.char_state("jessica").talks_seen == [first_id], "talk good +5")
	check(state.time_left == 3, "time is spent when the exchange finishes")
	check(db.text_label.text == first_exchange.choices[0].reply[0].text, "her reply plays")
	await _drain()
	check(state.time_left == 2, "talk costs 1")

	# Translation subtitle under Vietnamese lines, toggleable.
	db.play([{"speaker": "Jessica", "text": "Trời ơi.", "translation": "Oh my god."}])
	check(db.subtitle_label.visible and "Oh my god" in db.subtitle_label.text, "subtitle shown")
	convo.subtitles_toggle.button_pressed = false
	check(not db.subtitle_label.visible and not state.settings.subtitles, "subtitles toggle off")
	convo.subtitles_toggle.button_pressed = true
	await _drain()

	# Talk sometimes turns into her asking a question: right answer -> +7 and recorded.
	check(not convo.buttons.has("quiz") and convo.buttons.size() == 4, "one Talk button, no separate quiz")
	await _talk_question()
	check(state.time_left == 2, "the lead-in line costs nothing yet")
	var question: String = db.text_label.text
	var q: Dictionary = characters.profile("jessica").trivia().filter(func(t): return t.question == question)[0]
	opts = _choices()
	check(opts.size() == 4, "quiz shows 4 options")
	for b in opts:
		if b.text == q.answer:
			b.pressed.emit()
	await process_frame
	check(affection.value("jessica") == 12 and state.char_state("jessica").trivia_answered == [q.id],
		"quiz correct +7 (recorded by id)")
	check(q.get("min_affection", 0) <= 5, "only ungated questions at low affection")
	await _drain()
	check(state.time_left == 1, "a question costs 1, like any talk")
	check(convo.buttons.talk.disabled == false, "1 unit still affords talk")
	await _question_mix_checks()

	# Gift from inventory -> loved +15, her matching line, inventory decremented.
	convo.buttons.gift.pressed.emit()
	await process_frame
	opts = _choices()
	check(opts.size() == 7 and opts.back().text == "Never mind", "gift list from inventory")
	for b in opts:
		if b.text.begins_with("Taro Boba"):
			b.pressed.emit()
	await process_frame
	check(affection.value("jessica") == 27 and state.inventory.taro_boba == 0, "loved gift +15")
	check(db.text_label.text in characters.profile("jessica").data.dialogue.on_gift_loved, "gift reaction line")
	await _drain()
	check(state.time_left == 1, "gifts are free")
	await _journal_checks(q)

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
	check(not state.in_date and layer.screens.visible and layer.calendar.visible and not convo.visible,
		"back to the calendar after the date")
	check(not layer.bubble.visible, "her speech bubble goes away with the date")
	check(cal.slot_name() == "Afternoon" and state.time_left == 3, "the date used the rest of the morning")
	await _calendar_checks()


var cal: Node


## Data checks for the expanded profile: gating, soft facts, fact lines, coverage.
func _profile_content_checks() -> void:
	var j = characters.profile("jessica")
	check(j.trivia().size() == 26 and j.soft_facts().size() == 8, "26 trivia, 8 soft facts")
	check(j.trivia_available(0).size() == 18 and j.trivia_available(45).size() == 22
		and j.trivia_available(70).size() == 26, "trivia gated by min_affection")
	var taught := {}
	for e in characters.talk("jessica") + characters.fact_lines("jessica"):
		for t in e.teaches:
			taught[t] = true
	for f in j.soft_facts():
		taught[f.id] = true
	var untaught: Array = j.trivia().filter(func(q): return not taught.has(q.id)).map(func(q): return q.id)
	check(untaught.is_empty(), "every trivia answer is taught somewhere: missing %s" % [untaught])
	# The line that teaches the nickname keeps "anh" even before it's unlocked.
	var nick_line: Dictionary = characters.fact_lines("jessica").filter(func(f): return f.id == "nickname")[0].lines[0]
	check("anh" in j.normalize(nick_line, []).text, "nickname fact keeps 'anh'")
	check(not ("anh" in j.normalize(j.soft_facts().filter(func(f): return f.id == "biggest_fear")[0], []).text),
		"other lines still drop 'anh' until unlocked")
	check(j.normalize(j.soft_facts()[0], []).text == j.soft_facts()[0].reveal, "soft facts read their 'reveal'")


func _calendar_checks() -> void:
	_profile_content_checks()
	# 37 affection -> Curious: the boba shop is open, and that's where she is this afternoon.
	check(cal.location_unlocked("boba_shop") and not layer.calendar.location_buttons.boba_shop.disabled,
		"Curious unlocks the boba shop")
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await process_frame
	check(layer.calendar.visible and "nobody you know" in layer.calendar.message_label.text and state.time_left == 2,
		"empty location: message and travel costs 1")
	layer.calendar.location_buttons.boba_shop.pressed.emit()
	await process_frame
	check(convo.visible and convo.location_id == "boba_shop", "she's at the boba shop in the afternoon")
	await _drain()
	# Two talks use the last 2 units; the slot rolls over and the calendar comes back.
	# At 37 affection her first talk here is a soft fact (favorite food, unlocked at 20).
	convo.buttons.talk.pressed.emit()
	await process_frame
	check("Bún bò Huế" in convo.dialogue.text_label.text and _choices().is_empty(), "soft fact revealed at 20+")
	await _drain()
	check(convo.dialogue.text_label.text in characters.profile("jessica").data.dialogue.on_soft_fact_revealed,
		"she reacts after opening up")
	await _drain()
	check(state.char_state("jessica").soft_facts_seen == ["favorite_food"], "soft fact recorded")
	convo.buttons.talk.pressed.emit()
	await _drain()
	_choices()[1].pressed.emit()
	await _drain()
	await process_frame
	check(cal.slot_name() == "Evening" and layer.calendar.visible and "evening" in
		layer.calendar.message_label.text, "running out of time moves to the evening")
	check(not cal.location_unlocked("night_market"), "night market still locked at %d" % affection.value("jessica"))
	# Waiting skips a slot; at night she's nowhere.
	layer.calendar.wait_pressed.emit()
	await process_frame
	check(cal.slot_name() == "Night", "waiting moves to night")
	check(cal.characters_at("pho_spot") == ["jessica"] and cal.characters_at("night_owl_mart") == ["arisa"]
		and cal.characters_at("boba_shop").is_empty(), "night: Jessica at the phở spot, Arisa at Night Owl Mart")
	var ended := []
	bus.day_ended.connect(func(i): ended.append(i))
	layer.calendar.wait_pressed.emit()
	await process_frame
	check(cal.day_over and ended.size() == 1, "after night the day ends")

	# End-of-day summary.
	check(layer.summary.visible and not layer.calendar.visible, "summary shown when the day ends")
	var text: String = layer.summary.body.text
	var a: int = affection.value("jessica")
	check(not ("ffection" in text) and not ("Stage" in text) and not ("Curious" in text) and not (str(a) in text),
		"summary keeps affection a mystery")
	check("Unlocked: Boba Date Location" in text and not ("Intro Scene" in text), "summary: only unlocks earned today")
	check(layer.summary.menu_button.visible and layer.summary.menu_button.text == "Return to main menu",
		"summary offers a way back to the main menu")
	check("1 won, 0 lost" in text and "Trivia:  1 of 1 right" in text and "Gifts given: 1" in text,
		"summary: matches, trivia, gifts")
	check(layer.summary.title.text == "End of Day 1" and layer.summary.continue_button.text == "Start Day 2",
		"day 1 summary offers Day 2")
	await _multi_day_checks()
	await _debug_checks()
	await _second_character_checks()
	await _real_date_check()
	await _fact_line_check()
	await _two_girls_checks()
	await _compatibility_checks()
	await _save_load_checks()
	await _economy_checks()
	await _wardrobe_checks()


## Outfits: bought with story money (kept forever), worn everywhere once picked.
func _wardrobe_checks() -> void:
	var w: Node = root.get_node("Wardrobe")
	check(w.outfits.keys() == ["jessica", "arisa"] and w.outfits.jessica.size() == 5 and w.outfits.arisa.size() == 5,
		"outfits from data/outfits.json")
	for o in w.outfits.jessica + w.outfits.arisa:
		check(load(o.path) is Texture2D, "outfit image loads: %s" % o.path)
	check(w.is_owned("jessica") and w.is_owned("arisa") and not w.is_owned("jessica_maid"), "Classic is free")
	check(w.price("jessica_street") >= 150 and w.price("jessica_lace") >= 400, "outfits are expensive")
	bus.fire("new_story_requested")
	await process_frame
	layer.calendar.wardrobe_pressed.emit()
	var screen = layer.wardrobe
	check(screen.visible and screen.can_buy and screen.character_id == "jessica" and "$30" in screen.money_label.text,
		"wardrobe opens from the calendar with your money")
	check(screen.slots.jessica_street.button.disabled and screen.slots.jessica_street.button.text == "Buy  $150",
		"can't afford an outfit at the start")
	state.money = 500
	screen.refresh()
	screen.slots.jessica_maid.button.pressed.emit()
	check(w.is_owned("jessica_maid") and state.money == 500 - w.price("jessica_maid")
		and screen.slots.jessica_maid.button.text == "Wear", "buying an outfit costs story money")
	# Wear it: she wears it everywhere until it's taken off.
	screen.slots.jessica_maid.button.pressed.emit()
	check(w.worn("jessica") == "jessica_maid" and screen.slots.jessica_maid.button.text.begins_with("Wearing"),
		"wearing an outfit")
	var maid_path: String = w.outfit("jessica_maid").path
	check(w.look_path("jessica") == maid_path, "she wears it in conversations")
	for i in 10:
		check(w.match_path("jessica") == maid_path, "she wears it to every date")
	main._set_opponent(characters.profile("jessica").to_opponent())
	main.in_date = false
	main._start_match()
	check(main.portrait.texture.resource_path == maid_path, "and in Quickplay")
	main._show_menu()
	# Ownership and what she's wearing belong to the save slot's player, not the story.
	var saver: Node = root.get_node("SaveGame")
	state.reset_profile()
	saver.load_profile(saver.slot)
	check(w.is_owned("jessica_maid") and w.worn("jessica") == "jessica_maid", "the wardrobe is saved in the slot")
	bus.fire("new_story_requested")
	await process_frame
	check(w.is_owned("jessica_maid") and state.money == 30, "a new story keeps your outfits but not your money")
	# Take it off: she goes back to picking one of your outfits for each date.
	layer.calendar.wardrobe_pressed.emit()
	screen.slots.jessica_maid.button.pressed.emit()
	check(w.worn("jessica") == "", "taking it off")
	var seen := {}
	for i in 60:
		seen[w.match_path("jessica")] = true
	check(seen.keys().size() == 2 and seen.has(maid_path), "untouched: random among owned outfits")
	check(w.look_path("jessica") == w.outfit("jessica").path, "conversations default to Classic")
	screen.show_page("arisa")
	check(screen.slots.size() == 5 and screen.slots.has("arisa_muay_thai"), "Arisa's tab")
	screen.get_child(1).find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Close")[0].pressed.emit()
	check(not screen.visible and layer.calendar.visible, "closing returns to the calendar")
	# From the main menu: browse and wear, but no buying.
	layer.hide_all()
	bus.fire("wardrobe_requested")
	check(screen.visible and not screen.can_buy and screen.slots.jessica_lace.button.disabled
		and "Story Mode" in screen.slots.jessica_lace.button.text, "menu wardrobe can't buy")
	screen.get_child(1).find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Close")[0].pressed.emit()
	check(not layer.screens.visible, "closing the menu wardrobe returns to the menu")
	# Another slot is another player: their own wardrobe.
	layer.hide_all()
	bus.fire("new_story_requested", {"slot": 2})
	await process_frame
	check(saver.slot == 2 and not w.is_owned("jessica_maid") and w.worn("jessica") == ""
		and w.owned().size() == 2, "slot 2 has a fresh wardrobe: %s" % [w.owned()])
	layer.hide_all()
	bus.fire("continue_story_requested", {"slot": 1})
	await process_frame
	check(saver.slot == 1 and w.is_owned("jessica_maid"), "back in slot 1, the outfit is still owned")
	layer.hide_all()
	await _legacy_checks()
	_use_test_saves()
	layer.hide_all()


## Pre-slot saves (one story file, wardrobe.cfg, coin-era save.cfg) are imported into slot 1.
func _legacy_checks() -> void:
	var w: Node = root.get_node("Wardrobe")
	var saver: Node = root.get_node("SaveGame")
	_use_test_saves()
	check(not saver.has_slot(1) and saver.slot == 0 and w.owned().size() == 2, "no legacy files: no slots")
	# Coin-era outfits (old "abg" ids too; removed ones drop).
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR + f))
	var legacy := ConfigFile.new()
	legacy.set_value("progress", "coins", 5)
	legacy.set_value("progress", "unlocked", ["jessica", "abg_lace", "jessica_smile", "arisa_glam"])
	legacy.save(saver.legacy_progress_path)
	var old_story := {"version": 1, "day_over": false, "state": {"day": 2, "slot_index": 1, "time_left": 3, "money": 77,
		"characters": {"jessica": {"affection": 30, "met": true, "known_facts": ["age"], "gift_notes": {"loved": ["taro_boba"]}}}}}
	var f := FileAccess.open(saver.legacy_story_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old_story))
	f.close()
	saver.startup()
	check(saver.has_slot(1) and saver.slot == 1 and not saver.has_slot(2), "old saves become slot 1")
	check(w.is_owned("jessica_lace") and w.is_owned("arisa_glam") and not w.is_owned("jessica_maid")
		and not w.owned().has("jessica_smile") and w.is_owned("arisa"), "coin-era outfits carry over: %s" % [w.owned()])
	check(state.journal_state("jessica").known_facts == ["age"] and state.journal_state("jessica").met
		and state.journal_state("jessica").gift_notes.has("loved"), "the old journal moves into the profile")
	check(saver.load_game(1) and state.day == 2 and state.money == 77 and cal.slot_name() == "Afternoon",
		"the old story continues in slot 1")
	# Only once: deleting slot 1 doesn't bring the old save back.
	saver.delete_slot(1)
	saver.startup()
	check(not saver.has_slot(1) and saver.slot == 0, "migration runs once")


## Compatibility questions: she asks about you during Talk; the fit of your answer counts.
func _compatibility_checks() -> void:
	var jess = characters.profile("jessica")
	check(jess.compatibility_questions().size() == 10 and characters.profile("arisa").compatibility_questions().size() == 10,
		"both girls have compatibility questions")
	bus.fire("new_story_requested")
	await process_frame
	check(cal.location_background("pho_spot") != "" and load(cal.location_background("pho_spot")) is Texture2D
		and cal.location_background("muay_thai_gym") == "", "location backgrounds from schedule.json")
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await _drain()
	check(convo.backdrop.texture != null and convo.backdrop.texture.resource_path.ends_with("pho_spot.webp"),
		"the conversation shows the Phở Spot")
	var money: int = state.money
	config.data.conversation.compatibility_chance = 1.0
	convo.buttons.talk.pressed.emit()
	await _drain()
	var question: String = convo.dialogue.text_label.text
	var q: Array = jess.compatibility_questions().filter(func(x): return x.question == question)
	check(q.size() == 1 and q[0].get("min_affection", 0) == 0 and _choices().size() == 3,
		"Talk can turn into her asking about you: " + question)
	var good: Dictionary = q[0].options.filter(func(o): return o.fit == "good")[0]
	_choices().filter(func(b): return b.text == good.text)[0].pressed.emit()
	await process_frame
	check(convo.dialogue.text_label.text == good.reaction, "her reaction to your answer")
	await _drain()
	check(affection.value("jessica") == 6 and state.money == money + 10 and state.time_left == 2,
		"a good fit: +6 affection, +$10, costs 1 time")
	check(state.char_state("jessica").compat_answers.get(q[0].id, {}).get("fit") == "good", "answer recorded")
	# Never two questions in a row, never the same question twice, at most 2 a day.
	convo.buttons.talk.pressed.emit()
	await _drain()
	check(not jess.compatibility_questions().any(func(x): return x.question == convo.dialogue.text_label.text),
		"no question right after a question")
	if not _choices().is_empty():
		_choices()[0].pressed.emit()
	await _drain()
	state.char_state("jessica").erase("asked_last")
	state.time_left = 3
	convo.buttons.talk.pressed.emit()
	await _drain()
	var second: String = convo.dialogue.text_label.text
	var q2: Dictionary = jess.compatibility_questions().filter(func(x): return x.question == second)[0]
	check(second != question, "a different question")
	var bad: Dictionary = q2.options.filter(func(o): return o.fit == "bad")[0]
	var before: int = affection.value("jessica")
	_choices().filter(func(b): return b.text == bad.text)[0].pressed.emit()
	await _drain()
	check(affection.value("jessica") == before - 4, "a bad fit: -4")
	check(convo._compat_available().is_empty(), "two a day at most")
	state.day += 1
	check(convo._compat_available().size() == 3, "more tomorrow (unasked, ungated: %d)" % convo._compat_available().size())
	state.day -= 1
	config.data.conversation.compatibility_chance = 0.0
	state.char_state("jessica").erase("asked_last")
	convo._on_leave()
	layer.hide_all()
	# Old saves: the store and its toastie were renamed.
	state.from_dict({"location": "seven_eleven", "inventory": {"7_eleven_toastie": 2},
		"shop_stock": ["7_eleven_toastie", "taro_boba"]})
	check(state.location == "night_owl_mart" and state.inventory == {"night_owl_toastie": 2}
		and state.shop_stock == ["night_owl_toastie", "taro_boba"], "renamed ids in old saves")
	state.reset()


## Story money and the shop.
func _economy_checks() -> void:
	var eco: Node = root.get_node("Economy")
	bus.fire("new_story_requested")
	await process_frame
	check(state.money == 30 and state.shop_stock.size() == 6, "a new story starts with $30 and a stocked shop")
	check(state.shop_stock.all(func(i): return eco.price(i) > 0), "every stocked item has a price")
	check("$30" in layer.calendar.inventory_label.text, "calendar shows your money")
	# Earning: talk, right answers, dates.
	bus.fire("fact_learned", {"character_id": "jessica", "facts": ["age"], "source": "talk"})
	bus.fire("fact_learned", {"character_id": "jessica", "facts": ["age"], "source": "quiz"})
	bus.fire("trivia_answered", {"character_id": "jessica", "correct": true})
	bus.fire("trivia_answered", {"character_id": "jessica", "correct": false})
	check(state.money == 55, "talk +$10, right answer +$15, wrong answer $0 (got $%d)" % state.money)
	state.in_date = true
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "player", "score": [2, 0]})
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "opponent", "score": [0, 2]})
	state.in_date = false
	bus.fire("match_ended", {"opponent_id": "jessica", "winner": "player", "score": [2, 0]})
	check(state.money == 115, "date won +$40, lost +$20, quickplay $0 (got $%d)" % state.money)
	# Shopping.
	layer.calendar.shop_pressed.emit()
	check(layer.shop.visible and layer.shop.buy_buttons.size() == 6 and "$115" in layer.shop.money_label.text,
		"shop shows today's stock")
	var item: String = state.shop_stock[0]
	var have: int = state.inventory.get(item, 0)
	layer.shop.buy_buttons[item].pressed.emit()
	check(state.money == 115 - eco.price(item) and state.inventory[item] == have + 1, "buying adds the gift")
	check(not eco.buy("not_in_stock"), "can only buy what's in stock")
	state.money = 0
	layer.shop.refresh()
	check(layer.shop.buy_buttons.values().all(func(b): return b.disabled), "can't buy without money")
	check(not eco.buy(item) and state.inventory[item] == have + 1, "no money, no gift")
	state.money = 100
	layer.shop.get_child(1).find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Close")[0].pressed.emit()
	check(not layer.shop.visible and "$100" in layer.calendar.inventory_label.text, "closing the shop")
	# Money and stock survive save/load; the summary reports the day's money.
	var stock: Array = state.shop_stock.duplicate()
	root.get_node("SaveGame").save_game()
	state.money = 1
	state.shop_stock = []
	root.get_node("SaveGame").load_game()
	check(state.money == 100 and state.shop_stock == stock, "money and stock are saved")
	for i in 4:
		layer.calendar.wait_pressed.emit()
	await process_frame
	check("Money:  $100  (+70 today)" in layer.summary.body.text, "summary: money: " + layer.summary.body.text)
	layer.summary.continue_button.pressed.emit()
	check(state.day == 2 and state.shop_stock.size() == 6 and state.day_start_money == 100, "next morning restocks")
	root.get_node("SaveGame").delete_slot(1)
	layer.hide_all()


## Arisa: data, schedule conflicts, her conversation and her Second Wind.
func _two_girls_checks() -> void:
	# Every slot puts the girls somewhere different: picking one means missing the other.
	for slot in cal.slots():
		var j = cal.schedule.characters.jessica.get(slot.id)
		var a = cal.schedule.characters.arisa.get(slot.id)
		check(j != null and a != null and j != a, "%s: Jessica at %s, Arisa at %s" % [slot.id, j, a])
	for id in ["arisa", "jessica"]:
		var p = characters.profile(id)
		var taught := {}
		for e in characters.talk(id) + characters.fact_lines(id):
			for t in e.teaches:
				taught[t] = true
		for f in p.soft_facts():
			taught[f.id] = true
		var missing: Array = p.trivia().filter(func(q): return not taught.has(q.id)).map(func(q): return q.id)
		check(missing.is_empty(), "%s: every trivia answer is taught (missing %s)" % [id, missing])
		check(p.portrait() != "" and load(p.portrait()) is Texture2D, "%s: portrait loads" % id)

	var ari = characters.profile("arisa")
	check(ari.full_name() == "Arisa Wongsakul" and ari.to_opponent().signature_powerup == "second_wind",
		"Arisa's profile and signature power-up")
	check(not ("phi" in ari.line("on_game_win_player", [])) and "phi" in ari.line("on_game_win_player", ["nickname_phi"]),
		"she only calls you phi once it's unlocked")
	check(cal.lock_reason("thai_tea_shop") == "needs Friendly (20) with Arisa", "her locations say what they need")

	# Morning: Jessica's at the phở spot, Arisa's at the gym. Meet Arisa.
	bus.fire("new_story_requested")
	await process_frame
	check(layer.calendar.find_children("*", "ProgressBar", true, false).is_empty()
		and not layer.calendar.find_children("*", "Label", true, false).any(func(l): return "ffection" in l.text),
		"the calendar doesn't show affection")
	layer.calendar.location_buttons.muay_thai_gym.pressed.emit()
	await _drain()
	check(convo.character_id == "arisa" and convo.title_label.text.begins_with("Arisa"), "Arisa at the gym")
	convo.buttons.talk.pressed.emit()
	await process_frame
	var ari_first: String = state.char_state("arisa").order.exchanges[0]
	var ari_ex: Dictionary = characters.talk("arisa").filter(func(e): return e.id == ari_first)[0]
	check(convo.dialogue.text_label.text == ari.normalize(ari_ex.lines[0], []).text, "her small talk plays")
	await _drain()
	_choices()[0].pressed.emit()
	await _drain()
	check(affection.value("arisa") == 5 and affection.value("jessica") == 0, "affection is per girl")
	# A wrong answer doesn't give the right one away.
	await _talk_question()
	var question: String = convo.dialogue.text_label.text
	var q: Dictionary = ari.trivia().filter(func(t): return t.question == question)[0]
	_choices().filter(func(b): return b.text != q.answer)[0].pressed.emit()
	var shown := []
	for i in 30:
		await process_frame
		shown.append(convo.dialogue.text_label.text)
		if not convo.dialogue.is_busy():
			break
		convo.dialogue.advance()
	check(not shown.any(func(t): return q.answer in t), "wrong answer: the right one isn't revealed")
	check(shown.has(ari.data.dialogue.on_trivia_wrong[0].text if ari.data.dialogue.on_trivia_wrong[0] is Dictionary
		else ari.data.dialogue.on_trivia_wrong[0]), "she still reacts to the wrong answer")
	# A date with Arisa: no wardrobe outfits, so her profile portrait.
	convo.buttons.date.pressed.emit()
	await _drain()
	await process_frame
	var her_outfits: Array = root.get_node("Wardrobe").outfits_for("arisa").map(func(o): return o.path)
	check(main.opponent.id == "arisa" and her_outfits.has(main.portrait.texture.resource_path),
		"Arisa wears one of her own outfits to the date")
	check(main.opponent.tuning.get("two_hold_tendency") == 0.9, "her defensive card AI")
	var face_bottom: float = main.portrait.get_global_rect().position.y + main.portrait.get_global_rect().size.y * 0.4
	check(layer.bubble.get_global_rect().position.y > face_bottom
		and layer.bubble.get_global_rect().end.y <= main.nameplate.get_global_rect().position.y + 1,
		"her speech bubble sits by her feet, above her name: %s" % [layer.bubble.get_global_rect()])

	# Second Wind: she passed, the round is about to go to you, and she jumps back in.
	var R = load("res://scripts/rules.gd")
	main.hands[0] = [0, 40]
	main.hands[1] = [44, 8]
	main.last_combo = R.analyze([4])
	main.last_cards = [4]
	main.last_player = 0
	main.passed = [false, true]
	main.locked = [false, false]
	main.current = 1
	main.her_powerup_used = false
	var used := []
	var on_used := func(i): used.append(i)
	bus.powerup_used.connect(on_used)
	main._advance_turn()
	check(main.current == 1 and not main.passed[1] and main.pending_cpu_play.size() == 1
		and used.size() == 1 and used[0].id == "second_wind" and used[0].by == "opponent", "Second Wind")
	await process_frame
	check(layer.bubble.last_text in ari.data.dialogue.on_her_powerup, "she says her Second Wind line")
	main.pending_cpu_play = []
	main.passed = [false, true]
	main.current = 1
	main._advance_turn()
	check(main.current == 0 and used.size() == 1, "Second Wind is once per game")
	bus.powerup_used.disconnect(on_used)
	main._finish_date(false)
	await process_frame
	layer.hide_all()


func _save_load_checks() -> void:
	var saver: Node = root.get_node("SaveGame")
	for n in 3:
		saver.delete_slot(n + 1)
	check(saver.slot == 0, "no slots")
	# Story Mode opens the slot picker: three empty slots.
	bus.fire("story_menu_requested")
	var picker = layer.slots
	check(picker.visible and picker.rows.size() == 3 and picker.rows.values().all(
		func(r): return r.continue.disabled and r.delete.disabled and "Empty" in r.info.text), "three empty slots")
	picker.rows[1].new.pressed.emit()  # empty slot: no confirmation needed
	await process_frame
	check(not picker.visible and layer.calendar.visible and saver.slot == 1 and saver.has_slot(1),
		"New Story in an empty slot starts (and saves) a story there")
	# Time played: counted while in Story Mode, kept by the slot's player.
	state.profile.play_seconds = 0.0
	saver.tick(3725.0)
	saver.save_game()
	check(saver.slot_info(1).play_seconds == 3725 and saver.format_play_time(3725) == "1h 02m"
		and saver.format_play_time(75) == "1m", "time played is saved")
	layer.hide_all()
	saver.tick(500.0)
	check(int(state.profile.play_seconds) == 3725, "no time counts on the main menu")
	bus.fire("story_menu_requested")
	check("Time played 1h 02m" in picker.rows[1].info.text, "slot shows time played: " + picker.rows[1].info.text)
	picker.rows[1].continue.pressed.emit()
	await process_frame
	check(saver.playing, "Continue counts time again")
	affection.add("arisa", 23, "test")
	state.inventory.taro_boba = 0
	state.char_state("arisa").trivia_answered.append("age")
	cal.next_slot()  # autosaves
	check(saver.describe().begins_with("Day 1 of 3 · Afternoon"), "save description: " + saver.describe())
	bus.fire("story_menu_requested")
	check(not picker.rows[1].continue.disabled and "Day 1 of 3 · Afternoon" in picker.rows[1].info.text
		and picker.rows[2].continue.disabled, "slot 1 shows its story: " + picker.rows[1].info.text)
	picker.back_pressed.emit()
	check(not layer.screens.visible, "Back leaves the slot picker")
	# Change things (without advancing time, which would autosave), then load the save back.
	affection.add("arisa", 50, "test")
	state.slot_index = 3
	state.inventory.taro_boba = 5
	check(saver.load_game(), "load")
	check(state.slot_index == 1 and typeof(state.slot_index) == TYPE_INT and state.time_left == 3,
		"slot restored as int")
	check(affection.value("arisa") == 23 and typeof(affection.value("arisa")) == TYPE_INT, "affection restored")
	check(state.char_state("arisa").unlocks.has("thai_tea_date_location")
		and state.char_state("arisa").trivia_answered == ["age"] and state.inventory.taro_boba == 0,
		"unlocks, trivia and inventory restored")
	check(cal.location_unlocked("thai_tea_shop"), "loaded unlocks open her location")
	layer.hide_all()
	bus.fire("story_menu_requested")
	picker.rows[1].continue.pressed.emit()
	await process_frame
	check(layer.calendar.visible and cal.slot_name() == "Afternoon" and "Welcome back" in
		layer.calendar.message_label.text, "Continue resumes the slot's saved day")
	layer.calendar.save_pressed.emit()
	check("saved" in layer.calendar.message_label.text, "manual save")
	# Main menu from the calendar saves first.
	layer.calendar.menu_pressed.emit()
	check(not layer.screens.visible and saver.describe().begins_with("Day 1 of 3 · Afternoon"),
		"calendar 'Main menu' saves and leaves")
	bus.fire("continue_story_requested")
	await process_frame
	# A finished day: 'Return to main menu' from its summary, then Continue reopens that summary.
	cal.next_slot(); cal.next_slot(); cal.next_slot()
	await process_frame
	check(layer.summary.visible, "day summary")
	layer.summary.menu_button.pressed.emit()
	check(not layer.screens.visible, "summary 'Return to main menu' leaves the story")
	bus.fire("continue_story_requested")
	await process_frame
	check(layer.summary.visible and cal.day_over and state.day == 1, "continuing a finished day shows its summary")
	layer.hide_all()
	# A second slot is independent; New Story over an existing story asks first.
	bus.fire("story_menu_requested")
	picker.rows[2].new.pressed.emit()
	await process_frame
	check(saver.slot == 2 and state.day == 1 and cal.slot_name() == "Morning" and affection.value("arisa") == 0,
		"slot 2 is a separate story")
	layer.hide_all()
	bus.fire("story_menu_requested")
	check(saver.slot_info(1).day_over and not picker.rows[2].continue.disabled, "both slots listed")
	picker.rows[1].new.pressed.emit()
	check(picker.confirm.visible and "Slot 1" in picker.confirm.dialog_text and saver.slot == 2,
		"New Story over a story asks first")
	picker.confirm.confirmed.emit()
	await process_frame
	check(saver.slot == 1 and not cal.day_over and affection.value("arisa") == 0, "confirmed: slot 1 starts over")
	layer.hide_all()
	# Delete from the slot picker (asks first).
	bus.fire("story_menu_requested")
	picker.rows[2].delete.pressed.emit()
	check(picker.confirm.visible and "Delete Slot 2" in picker.confirm.dialog_text and saver.has_slot(2),
		"Delete asks first")
	picker.confirm.confirmed.emit()
	check(not saver.has_slot(2) and "Empty" in picker.rows[2].info.text and picker.rows[2].delete.disabled,
		"deleting a slot empties it")
	picker.rows[1].delete.pressed.emit()
	picker.confirm.confirmed.emit()
	check(not saver.has_slot(1) and saver.slot == 0 and state.profile.journal.is_empty(),
		"deleting the active slot clears the player's profile")
	layer.hide_all()


## After the small-talk exchanges run out, Talk moves on to one-line facts.
func _fact_line_check() -> void:
	bus.fire("new_story_requested")
	await process_frame
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await _drain()
	var st: Dictionary = state.char_state("jessica")
	for ex in characters.talk("jessica"):
		st.talks_seen.append(ex.id)
	convo.refresh()
	convo.buttons.talk.pressed.emit()
	await process_frame
	var fact_id: String = st.order.facts[0]
	var fact: Dictionary = characters.fact_lines("jessica").filter(func(f): return f.id == fact_id)[0]
	check(convo.dialogue.text_label.text == characters.profile("jessica").normalize(fact.lines[0], []).text
		and _choices().is_empty(), "fact line after exchanges")
	await _drain()
	check(st.talks_seen.has(fact_id) and state.time_left == 2, "fact line recorded and costs talk time")
	await _order_checks()
	layer.hide_all()


## Plays an actual Tiến Lên date to the end (her AI vs. Hint for you) from the calendar.
func _real_date_check() -> void:
	var seen := {}
	var recs := {}
	for e in bus.CARD_EVENTS + ["date_closed"]:
		recs[e] = func(_i): seen[e] = seen.get(e, 0) + 1
		bus.connect(e, recs[e])
	main.CPU_DELAY = 0.0
	bus.fire("new_story_requested")
	await process_frame
	layer.calendar.location_buttons.pho_spot.pressed.emit()
	await _drain()
	convo.buttons.date.pressed.emit()
	await _drain()
	var guard := 0
	while not seen.has("date_closed") and guard < 20000:
		guard += 1
		if main.overlay.visible:
			main._on_again_pressed()  # Next Game / Continue the day
		elif main.current == main.HUMAN and main.hands[main.HUMAN].size() > 0:
			main._on_hint_pressed()
			if main._selected_cards().is_empty():
				main._on_pass_pressed()
			else:
				main._on_play_pressed()
		await process_frame
	check(seen.get("match_started", 0) == 1 and seen.get("match_ended", 0) == 1, "real date: one match")
	check(seen.get("hand_won", 0) + seen.get("hand_lost", 0) > 3, "real date: hand events fired %s" % [seen])
	check(state.match_record.wins + state.match_record.losses == 1, "real date recorded")
	var base: int = config.int_value("affection.match_won" if state.match_record.wins == 1 else "affection.match_lost")
	check(affection.value("jessica") >= base, "real date affection (match result plus any bonuses)")
	check(cal.slot_name() == "Afternoon" and layer.calendar.visible, "real date ends the slot")
	print("real date events: ", seen, "  affection: ", affection.value("jessica"))
	for e in recs:
		bus.disconnect(e, recs[e])


## Days 2 and 3: a new morning, daily gifts, per-day stats, and the ending.
func _multi_day_checks() -> void:
	var aff_before: int = affection.value("jessica")
	var answered: Array = state.char_state("jessica").trivia_answered.duplicate()
	var pho_before: int = state.inventory.get("pho_takeout", 0)
	layer.summary.continue_button.pressed.emit()
	await process_frame
	check(state.day == 2 and cal.slot_name() == "Morning" and state.time_left == 3
		and layer.calendar.visible and not cal.day_over, "Day 2 starts in the morning")
	check(layer.calendar.title_label.text == "Day 2 of 3  ·  Morning", "calendar shows the day")
	check(affection.value("jessica") == aff_before and state.char_state("jessica").trivia_answered == answered,
		"affection and answered trivia carry over")
	check(state.inventory.get("pho_takeout", 0) == pho_before and state.shop_stock.size() == 6
		and state.day_start_money == state.money, "no free gifts: the shop restocks each morning instead")
	check(state.day_log.is_empty() and state.char_state("jessica").start_affection == aff_before,
		"day stats reset each morning")
	check(state.match_record.wins == 1, "story match record carries over")
	# Day 2: wait it out -> summary -> Day 3 -> final summary.
	for i in 4:
		layer.calendar.wait_pressed.emit()
	await process_frame
	check(layer.summary.visible and layer.summary.title.text == "End of Day 2"
		and "Date matches today:  0 won, 0 lost" in layer.summary.body.text, "day 2 summary shows day 2 only")
	layer.summary.continue_button.pressed.emit()
	await process_frame
	check(state.day == 3 and cal.is_final_day(), "Day 3")
	for i in 4:
		layer.calendar.wait_pressed.emit()
	await process_frame
	check(cal.story_over() and layer.summary.title.text == "The End"
		and layer.summary.continue_button.text == "Back to main menu"
		and "Over the whole story" in layer.summary.body.text
		and not ("ffection" in layer.summary.body.text) and not layer.summary.menu_button.visible, "final summary")
	cal.start_next_day()
	check(state.day == 3, "no Day 4")
	layer.summary.continue_button.pressed.emit()
	check(not layer.screens.visible and main.menu.visible, "the ending returns to the main menu")


func _debug_checks() -> void:
	var dbg = layer.debug_panel
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	layer._input(key)
	check(dbg.visible, "F1 opens the debug panel")
	for i in dbg.character_select.item_count:
		if dbg.character_select.get_item_text(i) == "jessica":
			dbg.character_select.select(i)
	bus.fire("new_story_requested")
	await process_frame
	var reached := []
	var on_reached := func(i): reached.append(i.stage.label)
	bus.affection_stage_reached.connect(on_reached)
	dbg.affection_spin.value = 75
	dbg.get_children()[0].find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Set")[0].pressed.emit()
	check(affection.value("jessica") == 75 and reached == ["Curious", "Into it", "Catching feelings"],
		"debug sets affection and fires stage events")
	check(cal.location_unlocked("night_market"), "debug affection unlocks the night market")
	bus.affection_stage_reached.disconnect(on_reached)
	var slot_before: int = state.slot_index
	dbg.find_children("*", "Button", true, false).filter(func(b): return b.text == "Next slot")[0].pressed.emit()
	check(state.slot_index == slot_before + 1, "debug jumps a time slot")
	# Firing card events by hand: with "treat as a date", a player bomb gives +2 and she reacts.
	dbg.in_date_check.button_pressed = true
	dbg.fire_card_event("bomb_played", {"by": "player"})
	await process_frame
	check(affection.value("jessica") == 77, "debug card event affects affection in a date")
	check(layer.bubble.last_text in characters.profile("jessica").data.dialogue.on_player_bomb,
		"debug card event triggers her reaction")
	dbg.in_date_check.button_pressed = false
	layer._input(key)
	check(not dbg.visible, "F1 closes the debug panel")
	layer.hide_all()


## A second character needs only data: a profile JSON plus a schedule entry.
func _second_character_checks() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_chars"))
	var mai := {"id": "mai", "name": "Mai Nguyễn", "date_locations": ["pho_spot"],
		"affection": {"max": 100, "stages": [{"min": 0, "label": "Shy", "unlocks": []},
			{"min": 10, "label": "Warming up", "unlocks": ["mai_secret"]}]},
		"gifts": {"loved": ["pho_takeout"], "affection_values": {"loved": 12}},
		"trivia": [{"question": "Favorite soup?", "answer": "Phở", "wrong": ["Bún bò", "Hủ tiếu"]}],
		"dialogue": {"greeting": ["Oh! Hi."], "on_player_bomb": ["Whoa!"]},
		"card_ai": {"tuning": {"aggression": 0.1}}}
	var f := FileAccess.open("user://test_chars/mai.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(mai))
	f.close()
	check(characters.load_character("user://test_chars/mai.json") == "mai", "new character registers")
	cal.schedule.characters["mai"] = {"morning": "pho_spot"}
	bus.fire("new_story_requested")
	await process_frame
	check(cal.characters_at("pho_spot").has("mai"), "schedule entry places her")
	convo.open("mai", "pho_spot", cal.location_name("pho_spot"))
	await _drain()
	check(convo.title_label.text.begins_with("Mai") and not convo.buttons.talk.disabled
		and not convo.buttons.date.disabled, "her conversation works (Talk asks her trivia)")
	convo.buttons.talk.pressed.emit()  # no small talk: her question comes up
	await _drain()
	check(convo.dialogue.text_label.text == "Favorite soup?" and _choices().size() == 3, "she asks her question")
	_choices()[0].pressed.emit()
	await _drain()
	check(convo.buttons.talk.disabled and "nothing new" in convo.buttons.talk.text, "then Talk runs out")
	bus.fire("gift_given", {"character_id": "mai", "gift_id": "pho_takeout", "category": "loved"})
	check(affection.value("mai") == 12 and state.char_state("mai").unlocks.has("mai_secret"),
		"her affection, stages and unlocks come from her JSON")
	check(characters.profile("mai").to_opponent().tuning.aggression == 0.1, "her card AI tuning")
	characters.profiles.erase("mai")
	cal.schedule.characters.erase("mai")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_chars/mai.json"))
	layer.hide_all()


func Rules_analyze_quad() -> Dictionary:
	var R = load("res://scripts/rules.gd")
	return R.analyze([24, 25, 26, 27])
