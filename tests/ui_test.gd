extends SceneTree
## Plays full games through the real main scene, driving the human seat with the
## Hint button. Run: godot --headless --path . --script res://tests/ui_test.gd

var main: Node
var games_done := 0


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("CPU_DELAY", 0.0)
	_run.call_deferred()


func _run() -> void:
	for players in [4, 2, 4, 2]:
		main._start_game(players)
		var guard := 0
		while not main.overlay.visible and guard < 5000:
			guard += 1
			if main.current == main.HUMAN and main.hands[main.HUMAN].size() > 0:
				main._on_hint_pressed()
				if main._selected_cards().is_empty():
					main._on_pass_pressed()
				else:
					main._on_play_pressed()
			await create_timer(0.01).timeout
		print("%d-player game finished=%s: %s" % [players, main.overlay.visible, main.result_label.text.replace("\n", " | ")])
		if not main.overlay.visible:
			print("FAIL: game stuck")
			quit(1)
			return
	quit(0)
