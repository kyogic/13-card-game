extends SceneTree
## Plays full games through the real main scene, driving the human seat with the
## Hint button and firing power-ups along the way.
## Run: godot --headless --path . --script res://tests/ui_test.gd

const Rules := preload("res://scripts/rules.gd")

const TEST_SAVE := "user://test_save.cfg"

var main: Node
var failures := 0


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = TEST_SAVE  # never touch the player's real save
	root.add_child(main)
	main.set("CPU_DELAY", 0.0)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _run() -> void:
	check(main.music_player.playing and main.music_player.stream.loop, "background music loops")
	_timer_unit_checks()
	_menu_checks()
	_music_checks()
	_match_and_wardrobe_checks()
	_event_checks()
	_powerup_unit_checks()
	for players in [4, 2, 4, 2, 4, 2, 4, 2]:
		main._start_game(players)
		var guard := 0
		while not main.overlay.visible and guard < 5000:
			guard += 1
			if main.current == main.HUMAN and main.hands[main.HUMAN].size() > 0:
				if randf() < 0.3:
					_try_random_powerup()
				main._on_hint_pressed()
				if main._selected_cards().is_empty():
					main._on_pass_pressed()
				else:
					main._on_play_pressed()
			await create_timer(0.01).timeout
		check(main.overlay.visible, "game stuck")
		check(main.powerup_uses_left >= 0, "power-up uses went negative")
		check(not main.game_running and "Game length:" in main.result_label.text, "timer stops and is reported")
		print("%d-player game: %s | power-ups used: %s" % [players,
			main.result_label.text.split("\n")[0], main.powerup_used.keys()])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _try_random_powerup() -> void:
	var key: String = main.POWERUPS.keys().pick_random()
	if key in ["suit_up", "lucky_draw", "wild"]:
		main._clear_selection()
		main.hand_views.pick_random().selected = true
	main._on_powerup_pressed(key)
	if main.pending_target_power != "":
		main._on_target_chosen(main._opponents_with_cards().pick_random())
	main._clear_selection()


## Deterministic checks of each power-up's effect.
## Records every EventBus card/navigation event as [name, info].
var events: Array = []
var recorders := {}
var bus: Node  # the EventBus autoload (test scripts compile before autoload names exist)


func _record(info: Dictionary, event: String) -> void:
	events.append([event, info])


func _names() -> Array:
	return events.map(func(e): return e[0])


func _event_checks() -> void:
	bus = root.get_node("EventBus")
	for e in bus.CARD_EVENTS + ["date_closed"]:
		recorders[e] = _record.bind(e)
		bus.connect(e, recorders[e])
	check(main.opponent.id == "jessica" and main.opponent_name == "Jessica", "default opponent from JSON")
	check(main.opponent.tuning.get("prefers_straights", false), "opponent carries card_ai tuning")

	# match_started fires with the opponent id.
	events.clear()
	main._start_match()
	check(_names() == ["match_started"] and events[0][1].opponent_id == "jessica", "match_started")
	check(main.nameplate.text == "Jessica Trần", "nameplate uses full name")

	# Round results: hand_won / hand_lost from the round winner.
	events.clear()
	main._emit_hand_result(0)
	main._emit_hand_result(1)
	check(_names() == ["hand_won", "hand_lost"], "hand_won / hand_lost")

	# two_saved: win a hand late while holding a dealt 2; only once per game.
	events.clear()
	main.dealt_twos = [Rules.RANK_TWO * 4]
	main.hands[0] = [0, 4, Rules.RANK_TWO * 4]
	main.two_saved_fired = false
	main._emit_hand_result(0)
	main._emit_hand_result(0)
	check(_names() == ["hand_won", "two_saved", "hand_won"], "two_saved once, late game")
	events.clear()
	main.hands[0] = [0, 4, 8, 12, Rules.RANK_TWO * 4]
	main.two_saved_fired = false
	main._emit_hand_result(0)
	check(_names() == ["hand_won"], "no two_saved early in the game")

	# bomb_played by either side.
	events.clear()
	main._track_play(0, Rules.analyze([_c("8", 0), _c("8", 1), _c("8", 2), _c("8", 3)]))
	main._track_play(1, Rules.analyze([_c("4", 0), _c("4", 1), _c("5", 0), _c("5", 1), _c("6", 0), _c("6", 1)]))
	check(_names() == ["bomb_played", "bomb_played"] and events[0][1].by == "player"
		and events[1][1].by == "opponent", "bomb_played by player and opponent")

	# powerup_used: the player's, and her signature Lead Steal.
	events.clear()
	main._start_game(2)
	main.current = 0
	main.required_card = -1
	main._on_powerup_pressed("lead_steal")
	check(events.size() == 1 and events[0][0] == "powerup_used" and events[0][1].by == "player"
		and events[0][1].id == "lead_steal" and events[0][1].first, "player powerup_used")
	main.lead_steal_armed = false
	events.clear()
	main.her_round_best = 12
	main.last_player = 0
	main._new_round(0)
	check(main.current == 1 and "powerup_used" in _names(), "her Lead Steal emits powerup_used")
	check(events.filter(func(e): return e[0] == "powerup_used")[0][1].by == "opponent", "...by opponent")

	# match_ended only when the best-of-3 is decided.
	events.clear()
	main._start_match()
	events.clear()
	main.finish_order = [0, 1]
	main.hands[0] = []
	main._end_game()
	check(not ("match_ended" in _names()), "no match_ended after game 1")
	main._start_game(2)
	main.finish_order = [0, 1]
	main.hands[0] = []
	main._end_game()
	var ended := events.filter(func(e): return e[0] == "match_ended")
	check(ended.size() == 1 and ended[0][1].winner == "player" and ended[0][1].score == [2, 0], "match_ended")

	# A date: requested by the dating layer, closed back to it after the match.
	events.clear()
	bus.fire("date_requested", {"character_id": "jessica", "opponent": main.opponent})
	check(main.in_date and main.table.visible and "match_started" in _names(), "date starts a match")
	main.match_wins = [1, 0]
	main.finish_order = [0, 1]
	main.hands[0] = []
	main._end_game()
	check(main.again_button.text == "Continue the day" and not main.overlay_menu_button.visible, "date result buttons")
	main._on_again_pressed()
	check(not main.in_date and _names().back() == "date_closed" and events.back()[1].completed, "date_closed")

	# 4-player games emit nothing about an opponent character.
	events.clear()
	main._start_game(4)
	main._emit_hand_result(0)
	main._track_play(0, Rules.analyze([_c("8", 0), _c("8", 1), _c("8", 2), _c("8", 3)]))
	check(events.is_empty(), "no character events in 4-player")
	for e in recorders:
		bus.disconnect(e, recorders[e])
	main._show_menu()


func _music_checks() -> void:
	check(main.music_slider != null and main.music_slider.value == main.music_volume * 100, "volume slider")
	main.music_slider.value = 0
	check(main.music_volume == 0.0 and main.music_player.stream_paused and main.music_value_label.text == "0%",
		"volume 0 pauses the music")
	main.music_slider.value = 80
	check(is_equal_approx(main.music_volume, 0.8) and not main.music_player.stream_paused
		and absf(main.music_player.volume_db - linear_to_db(0.8)) < 0.01, "volume 80%")
	var reloaded = load("res://scenes/main.tscn").instantiate()
	reloaded.save_path = TEST_SAVE
	root.add_child(reloaded)
	check(is_equal_approx(reloaded.music_volume, 0.8), "volume is saved")
	reloaded.queue_free()
	main.music_slider.value = 50


## Main menu: Story Mode and Quickplay pages.
func _menu_checks() -> void:
	main._show_menu()
	main._show_menu_page("main")
	check(main.menu_pages.main.visible and not main.menu_pages.quickplay.visible
		and not main.menu_pages.has("story"), "main page first")
	var labels := func(page): return page.find_children("*", "Button", true, false).map(func(b): return b.text)
	check(labels.call(main.menu_pages.main).has("Story Mode") and labels.call(main.menu_pages.main).has("Quickplay"),
		"main page has Story Mode and Quickplay")
	var asked := []
	var bus: Node = root.get_node("EventBus")
	var on_story := func(_info): asked.append(true)
	bus.story_menu_requested.connect(on_story)
	main.menu_pages.main.find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Story Mode")[0].pressed.emit()
	bus.story_menu_requested.disconnect(on_story)
	check(asked.size() == 1, "Story Mode asks the dating layer for the save slots")
	var quick: Array = labels.call(main.menu_pages.quickplay)
	check(quick.any(func(t): return t.begins_with("4 Players")) and quick.any(func(t): return t.begins_with("2 Players")),
		"Quickplay page has the 2- and 4-player games")
	check(not labels.call(main.menu_pages.main).any(func(t): return t.begins_with("4 Players")),
		"card games are no longer on the main page")
	main.menu_pages.main.find_children("*", "Button", true, false).filter(
		func(b): return b.text == "Quickplay")[0].pressed.emit()
	check(main.menu_pages.quickplay.visible and not main.menu_pages.main.visible, "Quickplay opens its page")
	main.menu_pages.quickplay.find_children("*", "Button", true, false).filter(
		func(b): return b.text.begins_with("4 Players"))[0].pressed.emit()
	check(main.table.visible and main.num_players == 4, "Quickplay starts a 4-player game")
	main._show_menu()
	main._show_menu_page("main")


func _timer_unit_checks() -> void:
	check(main._format_time(0) == "0:00", "format 0")
	check(main._format_time(75) == "1:15", "format 75")
	check(main._format_time(3725) == "1:02:05", "format 3725")


func _match_and_wardrobe_checks() -> void:
	check(not ("coins" in main) and not ("unlocked" in main), "the coin system is gone")
	main._start_match()
	check(main.names[1] == "Jessica" and main.portrait.visible and main.nameplate.visible, "Jessica shown in 2-player")
	check(main.portrait.texture != null, "Quickplay gets her portrait from the Wardrobe")
	check(main.portrait.get_parent() != main.table, "Jessica stands outside the table frame")
	check(main.table.get_global_rect().position.x >= main.portrait.get_global_rect().end.x,
		"table frame is to the right of Jessica")

	# You win game 1, Jessica wins game 2, you win game 3 -> match won (no rewards in Quickplay).
	main._record_match_result(0)
	check(main.again_button.text == "Next Game" and not main._match_over(), "match continues after 1-0")
	main._on_again_pressed()
	check(main.match_game == 2 and main.current == 0 and main.required_card == -1,
		"previous winner leads game 2")
	main._record_match_result(1)
	main._on_again_pressed()
	check(main.match_game == 3, "game 3 played at 1-1")
	var summary: String = main._record_match_result(0)
	check(main._match_over() and main.again_button.text == "New Match" and "You won the match!" in summary
		and not ("coin" in summary), "match won, no coin")
	main._on_again_pressed()
	check(main.match_game == 1 and main.match_wins == [0, 0], "new match resets score")
	main._show_menu()


func _powerup_unit_checks() -> void:
	main._start_game(2)
	main.current = main.HUMAN
	main.required_card = -1
	main._refresh_ui()

	# Suit Up turns the selected card into the Heart of its rank.
	var hand: Array = main.hands[0]
	var target := -1
	for c in hand:
		if c % 4 == 0:
			target = c
			break
	if target < 0:
		target = hand[0] if hand[0] % 4 != 3 else hand[1]
	main._clear_selection()
	for v in main.hand_views:
		if v.card == target:
			v.selected = true
			break
	main._on_powerup_pressed("suit_up")
	check(main.hands[0].has(target - target % 4 + 3) and main.powerup_used.has("suit_up"), "suit up -> heart")

	# Lucky Draw swaps a card with one from the dead pile (26 undealt cards in 2p).
	var dead_before: int = main.dead_pile.size()
	main.hand_views[0].selected = true
	var discarded: int = main.hand_views[0].card
	main._on_powerup_pressed("lucky_draw")
	check(main.dead_pile.size() == dead_before and main.dead_pile.has(discarded), "lucky draw")
	check(main.hands[0].size() == 13, "lucky draw keeps hand size")

	# Use limit: two used, the rest are blocked.
	check(main.powerup_uses_left == 0, "two uses consumed")
	check(main._powerup_block("wild") == "no uses left", "third power-up blocked")

	# Wild Card completes a straight: 5S 6S + wild 9C -> 5-6-7.
	_wild_check([_c("5", 0), _c("6", 0), _c("9", 1)], _c("9", 1), Rules.Type.STRAIGHT, _c("7", 3))
	# Wild Card completes a pair: JS + wild 3C -> pair of Jacks.
	_wild_check([_c("J", 0), _c("3", 1)], _c("3", 1), Rules.Type.PAIR, _c("J", 3))

	# Hand Lock / Lead Steal in a fresh game.
	main._start_game(4)
	main.current = main.HUMAN
	main._on_powerup_pressed("hand_lock")
	main._on_target_chosen(1)
	check(main.locked[1] and main.passed[1], "hand lock")

	main._start_game(4)
	main._on_powerup_pressed("lead_steal")
	check(main.lead_steal_armed, "lead steal armed")
	main.last_player = 2
	main._new_round(2)
	check(main.current == main.HUMAN and not main.lead_steal_armed, "lead steal fires")

	# Hand-Locked round winner loses the lead.
	main._start_game(4)
	main.last_player = 2
	main.last_combo = {"type": 1}
	main.locked[2] = true
	main.current = 1
	main.passed = [true, true, true, true]
	main._advance_turn()
	check(main.current == 3, "locked winner passes the lead (got %d)" % main.current)

	# Toggled-off power-ups can't be used.
	main.powerup_enabled["lead_steal"] = false
	main._start_game(4)
	check(main._powerup_block("lead_steal") == "off", "disabled power-up")
	main.powerup_enabled["lead_steal"] = true
	check(not main.POWERUPS.has("peek"), "peek removed")


func _c(rank_name: String, suit: int) -> int:
	return Rules.RANK_NAMES.find(rank_name) * 4 + suit


## Makes `wild` wild, plays `selection` as a fresh lead and checks the result.
func _wild_check(selection: Array, wild: int, expected_type: int, expected_top: int) -> void:
	main._start_game(2)
	main.current = main.HUMAN
	main.required_card = -1
	main.hands[0] = selection + [_c("K", 0), _c("K", 1)]
	main.hands[0].sort()
	main._rebuild_hand()
	for v in main.hand_views:
		v.selected = v.card == wild
	main._on_powerup_pressed("wild")
	check(main.wild_card == wild, "wild card set")
	for v in main.hand_views:
		v.selected = selection.has(v.card)
	check(main._play_error(main._selected_cards()) == "", "wild selection is playable")
	main._on_play_pressed()
	check(main.last_combo.get("type", -1) == expected_type and main.last_combo.top == expected_top,
		"wild resolved to %s" % [main.last_cards])
	check(main.hands[0].size() == 2 and main.wild_card == -1, "wild play removed cards from hand")
