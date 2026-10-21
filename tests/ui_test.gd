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
	_match_and_wardrobe_checks()
	_jessica_checks()
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
func _jessica_checks() -> void:
	var c = main.character
	check(c.full_name() == "Jessica Trần" and main.opponent_name == "Jessica", "profile loaded")
	check(main.nameplate.text == "Jessica Trần", "nameplate uses full name")

	# She only calls you "anh" once affection unlocks it.
	main.affection = 0
	check(not ("anh" in c.line("on_game_loss_player", 0)), "no 'anh' at low affection")
	check("anh" in c.line("on_game_loss_player", 50), "'anh' once unlocked")

	# Gifts: loved +15, disliked -5, each costs a coin.
	main.coins = 2
	main.give_gift("taro_boba")
	check(main.affection == 15 and main.coins == 1, "loved gift")
	main.give_gift("grocery_store_flowers")
	check(main.affection == 10 and main.coins == 0, "disliked gift")
	check(main.give_gift("taro_boba") == "" and main.affection == 10, "no gift without coins")

	# Reaching "Into it" (45) unlocks the Street outfit for free.
	main.unlocked = ["jessica"]
	main.affection = 40
	main._add_affection(7, "test")
	check(main.unlocked.has("jessica_street"), "stage unlock gives Street outfit")

	# Trivia: the right answer gives +7.
	main.affection = 0
	main._offer_trivia()
	var right := -1
	for i in main.trivia_buttons.size():
		if main.trivia_buttons[i].text == main.trivia_question.answer:
			right = i
	main._on_trivia_answer(right)
	check(main.affection == 7, "trivia correct")

	# Signature Lead Steal: after losing a round she played a 2 in.
	main._start_match()
	main.her_round_best = 12
	main.last_player = 0
	main._new_round(0)
	check(main.current == 1 and main.her_powerup_used and main.last_speech == "Nope. My lead now.",
		"Jessica steals the lead")
	main.her_round_best = 12
	main.last_player = 0
	main._new_round(0)
	check(main.current == 0, "her Lead Steal is once per game")

	# Profile screen shows the bracelet story once unlocked.
	main.affection = 75
	main._show_profile()
	check(main.profile_screen.visible and "bà ngoại" in main.profile_screen.story_label.text, "bracelet story")
	main.affection = 0
	main.coins = 0
	main.unlocked = ["jessica"]
	main._save_progress()
	main._show_menu()


func _timer_unit_checks() -> void:
	check(main._format_time(0) == "0:00", "format 0")
	check(main._format_time(75) == "1:15", "format 75")
	check(main._format_time(3725) == "1:02:05", "format 3725")


func _match_and_wardrobe_checks() -> void:
	check(main.coins == 0 and main.selected_outfit == "jessica", "fresh save defaults to Jessica")
	check(main.OUTFITS.size() == 6, "six Jessica outfits")
	for o in main.OUTFITS:
		check(load(o.path) is Texture2D, "outfit image loads: %s" % o.path)
	main._start_match()
	check(main.names[1] == "Jessica" and main.portrait.visible and main.nameplate.visible, "Jessica shown in 2-player")
	check(main.portrait.get_parent() != main.table, "Jessica stands outside the table frame")
	check(main.table.get_global_rect().position.x >= main.portrait.get_global_rect().end.x,
		"table frame is to the right of Jessica")

	# You win game 1, Jessica wins game 2, you win game 3 -> match won, +1 coin.
	main._record_match_result(0)
	check(main.again_button.text == "Next Game" and not main._match_over(), "match continues after 1-0")
	main._on_again_pressed()
	check(main.match_game == 2 and main.current == 0 and main.required_card == -1,
		"previous winner leads game 2")
	main._record_match_result(1)
	main._on_again_pressed()
	check(main.match_game == 3, "game 3 played at 1-1")
	main._record_match_result(0)
	check(main._match_over() and main.coins == 1 and main.again_button.text == "New Match", "match won gives coin")

	# Losing a match gives nothing.
	main._on_again_pressed()
	check(main.match_game == 1 and main.match_wins == [0, 0], "new match resets score")
	main._record_match_result(1)
	main._record_match_result(1)
	check(main._match_over() and main.coins == 1, "lost match gives no coin")

	# Spend the coin on an outfit; it becomes selected and is saved.
	main._show_wardrobe()
	check(not main.wardrobe_slots["jessica_maid"].button.disabled, "can afford unlock")
	main._on_outfit_pressed("jessica_maid")
	check(main.coins == 0 and main.unlocked.has("jessica_maid") and main.selected_outfit == "jessica_maid", "unlock")
	check(main.wardrobe_slots["jessica_smile"].button.disabled, "can't unlock without coins")
	main._on_outfit_pressed("jessica_smile")
	check(not main.unlocked.has("jessica_smile"), "no free unlocks")
	var reloaded = load("res://scenes/main.tscn").instantiate()
	reloaded.save_path = TEST_SAVE
	root.add_child(reloaded)
	check(reloaded.selected_outfit == "jessica_maid" and reloaded.unlocked.has("jessica_maid"), "progress saved")
	reloaded.queue_free()
	# Old saves used "abg" ids; they are migrated on load.
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("progress", "coins", 3)
	old_cfg.set_value("progress", "unlocked", ["abg", "abg_maid"])
	old_cfg.set_value("progress", "selected_outfit", "abg_maid")
	old_cfg.save("user://test_old_save.cfg")
	var migrated = load("res://scenes/main.tscn").instantiate()
	migrated.save_path = "user://test_old_save.cfg"
	root.add_child(migrated)
	check(migrated.unlocked == ["jessica", "jessica_maid"] and migrated.selected_outfit == "jessica_maid",
		"old abg save migrates")
	migrated.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_old_save.cfg"))
	main._on_outfit_pressed("jessica")
	check(main.selected_outfit == "jessica", "re-select owned outfit for free")
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
