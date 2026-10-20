extends Control
## Tien Len prototype: menu, table UI and turn flow. The whole UI is built in code.

const Rules := preload("res://scripts/rules.gd")
const AI := preload("res://scripts/ai.gd")
const CardView := preload("res://scripts/card_view.gd")

const HUMAN := 0
var CPU_DELAY := 0.9
const PLACE_NAMES := ["1st", "2nd", "3rd", "4th"]
const TURN_COLOR := Color(1.0, 0.85, 0.2)
const IDLE_COLOR := Color(0.9, 0.95, 0.9)

# --- Game state -------------------------------------------------------------
var num_players := 4
var names: Array = []
var hands: Array = []          # Array of Array[int], kept sorted
var passed: Array = []         # passed[p] == true -> out until the round resets
var finish_order: Array = []   # players in the order they emptied their hands
var current := 0
var last_combo := {}           # empty -> current player leads freely
var last_cards: Array = []
var last_player := -1
var required_card := -1        # lowest dealt card; must be in the opening play
var game_id := 0               # bumped on every new game to cancel pending CPU turns
var log_lines: Array = []

# --- UI ---------------------------------------------------------------------
var menu: Control
var table: Control
var seats: Array = []          # per player: {box, name_label, backs, info_label}
var pile_label: Label
var pile_cards: HBoxContainer
var hand_area: Control
var hand_views: Array = []
var status_label: Label
var log_label: Label
var play_button: Button
var pass_button: Button
var hint_button: Button
var clear_button: Button
var overlay: Control
var result_label: Label


func _ready() -> void:
	randomize()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.36, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_menu()
	_build_table()
	_build_overlay()
	_show_menu()


# ============================================================================
# UI construction
# ============================================================================

func _build_menu() -> void:
	menu = CenterContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	menu.add_child(box)

	box.add_child(_make_label("TIEN LEN", 64, Color(1, 0.9, 0.4)))
	box.add_child(_make_label("Thirteen — Vietnamese card game", 22, IDLE_COLOR))
	box.add_child(_spacer(12))
	var four := _make_button("4 Players  —  You vs 3 CPU (full deck)", 24)
	four.pressed.connect(_start_game.bind(4))
	box.add_child(four)
	var two := _make_button("2 Players  —  You vs 1 CPU (half deck)", 24)
	two.pressed.connect(_start_game.bind(2))
	box.add_child(two)
	var quit := _make_button("Quit", 20)
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	box.add_child(_spacer(12))
	var rules := _make_label(
		"Get rid of all your cards first.  3 is low, 2 is high.  Suits: Spades < Clubs < Diamonds < Hearts.\n" +
		"Play singles, pairs, triples, four-of-a-kind, straights (3+) or 3+ consecutive pairs.\n" +
		"Beat the table with the same kind and size but a higher top card, or pass.\n" +
		"Passing locks you out until the round resets.  Bombs (4-of-a-kind, consecutive pairs) chop 2s.",
		15, Color(0.85, 0.92, 0.85))
	box.add_child(rules)


func _build_table() -> void:
	table = Control.new()
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)

	# Centre pile.
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -330
	center.offset_right = 330
	center.offset_top = -140
	center.offset_bottom = 40
	table.add_child(center)
	pile_label = _make_label("", 20, IDLE_COLOR)
	center.add_child(pile_label)
	pile_cards = HBoxContainer.new()
	pile_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	pile_cards.add_theme_constant_override("separation", 6)
	pile_cards.custom_minimum_size = Vector2(0, 104)
	center.add_child(pile_cards)

	# Bottom: status, buttons and the player's hand.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -230
	bottom.offset_bottom = -8
	bottom.add_theme_constant_override("separation", 8)
	table.add_child(bottom)
	status_label = _make_label("", 20, TURN_COLOR)
	bottom.add_child(status_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	bottom.add_child(buttons)
	play_button = _make_button("Play", 20)
	play_button.pressed.connect(_on_play_pressed)
	pass_button = _make_button("Pass", 20)
	pass_button.pressed.connect(_on_pass_pressed)
	hint_button = _make_button("Hint", 20)
	hint_button.pressed.connect(_on_hint_pressed)
	clear_button = _make_button("Clear", 20)
	clear_button.pressed.connect(_clear_selection)
	for b in [play_button, pass_button, hint_button, clear_button]:
		b.custom_minimum_size = Vector2(110, 40)
		buttons.add_child(b)
	hand_area = Control.new()
	hand_area.custom_minimum_size = Vector2(0, 130)
	hand_area.resized.connect(_layout_hand)
	bottom.add_child(hand_area)

	# Event log (top-left) and menu button (top-right).
	log_label = Label.new()
	log_label.position = Vector2(12, 10)
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.85))
	table.add_child(log_label)
	var menu_button := _make_button("Menu", 16)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.offset_left = -90
	menu_button.offset_right = -12
	menu_button.offset_top = 10
	menu_button.offset_bottom = 44
	menu_button.pressed.connect(_show_menu)
	table.add_child(menu_button)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(_make_label("Game Over", 44, Color(1, 0.9, 0.4)))
	result_label = _make_label("", 24, Color.WHITE)
	box.add_child(result_label)
	var again := _make_button("Play Again", 22)
	again.pressed.connect(func(): _start_game(num_players))
	box.add_child(again)
	var back := _make_button("Main Menu", 22)
	back.pressed.connect(_show_menu)
	box.add_child(back)


## Creates the opponent/you seat widgets for the current player count.
func _build_seats() -> void:
	for s in seats:
		s.box.queue_free()
	seats.clear()
	# Counter-clockwise turn order: you (bottom) -> right -> top -> left.
	var presets := [Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER_RIGHT,
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_LEFT]
	if num_players == 2:
		presets = [Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER_TOP]
	for p in num_players:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := _make_label(names[p], 20, IDLE_COLOR)
		var info_label := _make_label("", 16, IDLE_COLOR)
		var backs := HBoxContainer.new()
		backs.alignment = BoxContainer.ALIGNMENT_CENTER
		backs.add_theme_constant_override("separation", -26)
		box.add_child(name_label)
		if p != HUMAN:
			box.add_child(backs)
		box.add_child(info_label)
		table.add_child(box)
		box.set_anchors_and_offsets_preset(presets[p], Control.PRESET_MODE_KEEP_SIZE)
		match presets[p]:
			Control.PRESET_CENTER_TOP:
				_set_offsets(box, -200, 200, 10, 130)
			Control.PRESET_CENTER_LEFT:
				_set_offsets(box, 20, 260, -150, -30)
			Control.PRESET_CENTER_RIGHT:
				_set_offsets(box, -260, -20, -150, -30)
			Control.PRESET_CENTER_BOTTOM:
				# Your seat is just a name tag at the bottom-left above the hand.
				box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
				_set_offsets(box, 20, 220, -230, -170)
		seats.append({"box": box, "name_label": name_label, "backs": backs, "info_label": info_label})


func _set_offsets(c: Control, l: float, r: float, t: float, b: float) -> void:
	c.offset_left = l
	c.offset_right = r
	c.offset_top = t
	c.offset_bottom = b


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _show_menu() -> void:
	game_id += 1
	menu.visible = true
	table.visible = false
	overlay.visible = false


# ============================================================================
# Game flow
# ============================================================================

func _start_game(players: int) -> void:
	game_id += 1
	num_players = players
	names = ["You"]
	for i in range(1, players):
		names.append("CPU %d" % i if players > 2 else "CPU")

	# Deal 13 each. With 2 players only 26 cards (half the deck) are in play.
	var deck := Rules.new_deck()
	deck.shuffle()
	hands = []
	for p in players:
		var hand := deck.slice(p * 13, p * 13 + 13)
		hand.sort()
		hands.append(hand)

	passed = []
	passed.resize(players)
	passed.fill(false)
	finish_order = []
	last_combo = {}
	last_cards = []
	last_player = -1
	log_lines = []

	# Lowest card dealt (3♠ in a full game) opens the game and must be played.
	required_card = 52
	for p in players:
		if hands[p][0] < required_card:
			required_card = hands[p][0]
			current = p

	menu.visible = false
	overlay.visible = false
	table.visible = true
	_build_seats()
	_log("New %d-player game. %s the %s and %s." % [
		players, "You hold" if current == HUMAN else names[current] + " holds",
		Rules.card_name(required_card), "open" if current == HUMAN else "opens"])
	_rebuild_hand()
	_start_turn()


func _start_turn() -> void:
	_refresh_ui()
	if current == HUMAN:
		return
	var my_game := game_id
	await get_tree().create_timer(CPU_DELAY).timeout
	if my_game != game_id:
		return  # game was restarted or abandoned while waiting
	var cards := AI.choose_play(hands[current], last_combo, required_card, _danger_for(current))
	if cards.is_empty():
		_do_pass(current)
	else:
		_do_play(current, cards)


func _do_play(p: int, cards: Array) -> void:
	var combo := Rules.analyze(cards)
	for c in cards:
		hands[p].erase(c)
	cards = cards.duplicate()
	cards.sort()
	last_combo = combo
	last_cards = cards
	last_player = p
	required_card = -1
	_log("%s played %s." % [names[p], Rules.type_name(combo)])

	if hands[p].is_empty():
		finish_order.append(p)
		_log("%s is out of cards — %s place!" % [names[p], PLACE_NAMES[finish_order.size() - 1]])
	if p == HUMAN:
		_rebuild_hand()
	if hands[p].is_empty() and _active_players().size() <= 1:
		_end_game()
		return
	_advance_turn()
	_start_turn()


func _do_pass(p: int) -> void:
	passed[p] = true
	_log("%s passed." % names[p])
	_advance_turn()
	_start_turn()


## Moves to the next player still in the round. When play comes back around to the
## last player who played, everyone else has passed and a fresh round begins.
func _advance_turn() -> void:
	var i := current
	for _step in num_players:
		i = (i + 1) % num_players
		if i == last_player:
			_new_round(i if hands[i].size() > 0 else _next_active(i))
			return
		if hands[i].size() > 0 and not passed[i]:
			current = i
			return
	_new_round(_next_active(current))


func _new_round(leader: int) -> void:
	passed.fill(false)
	last_combo = {}
	last_cards = []
	last_player = -1
	current = leader
	_log("Everyone passed — %s leads a new round." % names[leader])


func _next_active(from: int) -> int:
	var i := from
	for _step in num_players:
		i = (i + 1) % num_players
		if hands[i].size() > 0:
			return i
	return from


func _active_players() -> Array:
	var result := []
	for p in num_players:
		if hands[p].size() > 0:
			result.append(p)
	return result


## Fewest cards held by any other player still in the game.
func _danger_for(p: int) -> int:
	var fewest := 99
	for q in num_players:
		if q != p and hands[q].size() > 0:
			fewest = mini(fewest, hands[q].size())
	return fewest


func _end_game() -> void:
	game_id += 1
	for p in _active_players():
		finish_order.append(p)
	_refresh_ui()
	var lines := []
	for i in finish_order.size():
		lines.append("%s  —  %s" % [PLACE_NAMES[i], names[finish_order[i]]])
	var headline := "You win!" if finish_order[0] == HUMAN else "%s wins." % names[finish_order[0]]
	result_label.text = headline + "\n\n" + "\n".join(lines)
	overlay.visible = true


# ============================================================================
# Human input
# ============================================================================

func _selected_cards() -> Array:
	var result := []
	for v in hand_views:
		if v.selected:
			result.append(v.card)
	return result


func _on_card_clicked(view) -> void:
	if current != HUMAN:
		return
	view.selected = not view.selected
	_layout_hand()
	_refresh_buttons()


func _on_play_pressed() -> void:
	var cards := _selected_cards()
	if current != HUMAN or _play_error(cards) != "":
		return
	_do_play(HUMAN, cards)


func _on_pass_pressed() -> void:
	if current != HUMAN or last_combo.is_empty():
		return
	_clear_selection()
	_do_pass(HUMAN)


func _on_hint_pressed() -> void:
	if current != HUMAN:
		return
	var cards := AI.choose_play(hands[HUMAN], last_combo, required_card, 0)
	for v in hand_views:
		v.selected = cards.has(v.card)
	_layout_hand()
	_refresh_buttons()
	if cards.is_empty():
		status_label.text = "Nothing in your hand beats that — you'll have to pass."


func _clear_selection() -> void:
	for v in hand_views:
		v.selected = false
	_layout_hand()
	_refresh_buttons()


## Returns why the selection can't be played, or "" if it can.
func _play_error(cards: Array) -> String:
	if cards.is_empty():
		return "Select cards to play."
	var combo := Rules.analyze(cards)
	if not Rules.is_valid(combo):
		return "That isn't a valid combination."
	if required_card >= 0 and not cards.has(required_card):
		return "The opening play must include the %s." % Rules.card_name(required_card)
	if not Rules.can_beat(combo, last_combo):
		return "%s doesn't beat the table." % Rules.type_name(combo)
	return ""


# ============================================================================
# UI refresh
# ============================================================================

func _rebuild_hand() -> void:
	for v in hand_views:
		v.queue_free()
	hand_views.clear()
	for c in hands[HUMAN]:
		var v := CardView.new()
		v.setup(c, true, true)
		v.clicked.connect(_on_card_clicked)
		hand_area.add_child(v)
		hand_views.append(v)
	_layout_hand()


func _layout_hand() -> void:
	var n := hand_views.size()
	if n == 0:
		return
	var w := CardView.CARD_SIZE.x
	var spacing := minf(w + 8, (hand_area.size.x - 40 - w) / maxf(n - 1, 1))
	var total := spacing * (n - 1) + w
	var x0 := (hand_area.size.x - total) * 0.5
	for i in n:
		var v = hand_views[i]
		v.position = Vector2(x0 + spacing * i, 4 if v.selected else 24)


func _refresh_ui() -> void:
	# Seats.
	for p in num_players:
		var seat: Dictionary = seats[p]
		var is_turn: bool = p == current and overlay.visible == false and hands[p].size() > 0
		seat.name_label.add_theme_color_override("font_color", TURN_COLOR if is_turn else IDLE_COLOR)
		seat.name_label.text = ("> " if is_turn else "") + names[p]
		var place := finish_order.find(p)
		var info := "%d cards" % hands[p].size()
		if place >= 0:
			info = "%s place" % PLACE_NAMES[place]
		elif passed[p]:
			info += "  ·  passed"
		seat.info_label.text = info
		if p != HUMAN:
			var backs: HBoxContainer = seat.backs
			for child in backs.get_children():
				child.queue_free()
			for i in hands[p].size():
				var back := CardView.new()
				back.setup(-1, false, false, 0.45)
				backs.add_child(back)

	# Centre pile.
	for child in pile_cards.get_children():
		child.queue_free()
	if last_cards.is_empty():
		pile_label.text = "%s to lead — any combination" % names[current]
	else:
		pile_label.text = "%s: %s" % [names[last_player], Rules.type_name(last_combo)]
		for c in last_cards:
			var v := CardView.new()
			v.setup(c, true, false)
			pile_cards.add_child(v)

	log_label.text = "\n".join(log_lines)
	_refresh_buttons()


func _refresh_buttons() -> void:
	var my_turn: bool = current == HUMAN and hands[HUMAN].size() > 0 and table.visible
	play_button.disabled = not my_turn or _play_error(_selected_cards()) != ""
	pass_button.disabled = not my_turn or last_combo.is_empty()
	hint_button.disabled = not my_turn
	clear_button.disabled = not my_turn
	if hands[HUMAN].is_empty():
		status_label.text = "You're out! Watching the CPUs finish..."
	elif not my_turn:
		status_label.text = "Waiting for %s..." % names[current]
	else:
		var err := _play_error(_selected_cards())
		if _selected_cards().is_empty():
			if required_card >= 0:
				status_label.text = "Your turn — open with a play containing the %s." % Rules.card_name(required_card)
			elif last_combo.is_empty():
				status_label.text = "Your turn — lead any combination."
			else:
				status_label.text = "Your turn — beat the %s or pass." % Rules.type_name(last_combo)
		elif err != "":
			status_label.text = err
		else:
			status_label.text = "Ready: %s" % Rules.type_name(Rules.analyze(_selected_cards()))


func _log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > 8:
		log_lines.pop_front()
	print(line)
