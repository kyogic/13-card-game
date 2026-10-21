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
