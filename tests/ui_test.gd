extends SceneTree
## Plays full games through the real main scene, driving the human seat with the
## Hint button and firing power-ups along the way.
## Run: godot --headless --path . --script res://tests/ui_test.gd

var main: Node
var failures := 0


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("CPU_DELAY", 0.0)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _run() -> void:
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
		print("%d-player game: %s | power-ups used: %s" % [players,
			main.result_label.text.split("\n")[0], main.powerup_used.keys()])
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _try_random_powerup() -> void:
	var key: String = main.POWERUPS.keys().pick_random()
	if key in ["suit_up", "lucky_draw"]:
		main._clear_selection()
		main.hand_views.pick_random().selected = true
	main._on_powerup_pressed(key)
	if main.pending_target_power != "":
		main._on_target_chosen(main._opponents_with_cards().pick_random())
	main._clear_selection()


## Deterministic checks of each power-up's effect.
func _powerup_unit_checks() -> void:
	main._start_game(2)
	main.current = main.HUMAN
	main.required_card = -1
	main._refresh_ui()

	# Suit Up raises the selected card one suit.
	var hand: Array = main.hands[0]
	var target := -1
	for c in hand:
		if c % 4 != 3:
			target = c
			break
	main._clear_selection()
	for v in main.hand_views:
		if v.card == target:
			v.selected = true
			break
	main._on_powerup_pressed("suit_up")
	check(main.hands[0].has(target + 1) and main.powerup_used.has("suit_up"), "suit up")

	# Lucky Draw swaps a card with one from the dead pile (26 undealt cards in 2p).
	var dead_before: int = main.dead_pile.size()
	main.hand_views[0].selected = true
	var discarded: int = main.hand_views[0].card
	main._on_powerup_pressed("lucky_draw")
	check(main.dead_pile.size() == dead_before and main.dead_pile.has(discarded), "lucky draw")
	check(main.hands[0].size() == 13, "lucky draw keeps hand size")

	# Use limit: two used, the rest are blocked.
	check(main.powerup_uses_left == 0, "two uses consumed")
	check(main._powerup_block("peek") == "no uses left", "third power-up blocked")

	# Peek / Hand Lock / Lead Steal in a fresh game.
	main._start_game(4)
	main.current = main.HUMAN
	main._on_powerup_pressed("peek")
	main._on_target_chosen(2)
	check(main.peek_player == 2 and main.peek_cards.size() == 3, "peek")
	for c in main.peek_cards:
		check(main.hands[2].has(c), "peeked card is in hand")
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
	main.powerup_enabled["peek"] = false
	main._start_game(4)
	check(main._powerup_block("peek") == "off", "disabled power-up")
	main.powerup_enabled["peek"] = true
