extends Control
## Tien Len prototype: menu, table UI and turn flow. The whole UI is built in code.

const Rules := preload("res://scripts/rules.gd")
const AI := preload("res://scripts/ai.gd")
const CardView := preload("res://scripts/card_view.gd")
const MUSIC := preload("res://audio/cardgame_song.mp3")

const HUMAN := 0
var CPU_DELAY := 0.9
const PLACE_NAMES := ["1st", "2nd", "3rd", "4th"]
const TURN_COLOR := Color(1.0, 0.85, 0.2)
const IDLE_COLOR := Color(0.9, 0.95, 0.9)
const MAX_POWERUP_USES := 2
## key -> [button name, description]. Each power-up can be used once per game.
const POWERUPS := {
	"peek": ["Peek (Nhìn Lén)", "See three random cards in an opponent's hand."],
	"suit_up": ["Suit Up", "Raise one card's suit a level (Spades -> Clubs -> Diamonds -> Hearts)."],
	"lucky_draw": ["Lucky Draw", "Discard one card and draw a random one from the dead pile."],
	"lead_steal": ["Lead Steal", "Take the lead at the start of the next round, whoever won it."],
	"hand_lock": ["Hand Lock", "Lock an opponent out for the rest of this round."],
}

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

# --- Power-ups (human only) -------------------------------------------------
var powerup_enabled := {}      # key -> bool, set by the main-menu toggles
var powerup_used := {}         # key -> true once used this game
var powerup_uses_left := MAX_POWERUP_USES
var dead_pile: Array = []      # undealt cards + cleared tricks + discards
var locked: Array = []         # locked[p] == true -> Hand Lock until the round resets
var lead_steal_armed := false
var peek_player := -1
var peek_cards: Array = []
var pending_target_power := ""
var flash_text := ""           # one-shot status message shown on the next refresh
var game_start_ms := 0
var game_running := false

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
var powerup_title: Label
var powerup_buttons := {}      # key -> Button
var target_menu: PopupMenu
var timer_label: Label
var music_player: AudioStreamPlayer


func _ready() -> void:
	randomize()
	for key in POWERUPS:
		powerup_enabled[key] = true
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.36, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_start_music()
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
	box.add_theme_constant_override("separation", 10)
	menu.add_child(box)

	box.add_child(_make_label("TIEN LEN", 52, Color(1, 0.9, 0.4)))
	box.add_child(_make_label("Thirteen — Vietnamese card game", 20, IDLE_COLOR))
	box.add_child(_spacer(6))
	var four := _make_button("4 Players  —  You vs 3 CPU (full deck)", 24)
	four.pressed.connect(_start_game.bind(4))
	box.add_child(four)
	var two := _make_button("2 Players  —  You vs 1 CPU (half deck)", 24)
	two.pressed.connect(_start_game.bind(2))
	box.add_child(two)
	var quit := _make_button("Quit", 20)
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	box.add_child(_spacer(6))
	box.add_child(_make_label("Power-ups  (toggle on/off — each usable once, up to %d per game)" % MAX_POWERUP_USES,
		18, Color(1, 0.9, 0.4)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 0)
	for key in POWERUPS:
		var toggle := CheckButton.new()
		toggle.text = POWERUPS[key][0]
		toggle.button_pressed = powerup_enabled[key]
		toggle.add_theme_font_size_override("font_size", 16)
		toggle.toggled.connect(func(on): powerup_enabled[key] = on)
		grid.add_child(toggle)
		var desc := _make_label(POWERUPS[key][1], 14, Color(0.85, 0.92, 0.85))
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(desc)
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	box.add_child(grid_center)
	var music_toggle := CheckButton.new()
	music_toggle.text = "Background music"
	music_toggle.button_pressed = true
	music_toggle.add_theme_font_size_override("font_size", 16)
	music_toggle.toggled.connect(func(on): music_player.stream_paused = not on)
	var music_center := CenterContainer.new()
	music_center.add_child(music_toggle)
	box.add_child(music_center)
	box.add_child(_spacer(6))
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
	timer_label = _make_label("", 20, IDLE_COLOR)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(timer_label, -260, -100, 12, 42)
	table.add_child(timer_label)

	# Power-up panel (top-right, under the menu button).
	var power_box := VBoxContainer.new()
	power_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(power_box, -230, -12, 52, 250)
	power_box.add_theme_constant_override("separation", 4)
	table.add_child(power_box)
	powerup_title = _make_label("", 16, Color(1, 0.9, 0.4))
	power_box.add_child(powerup_title)
	for key in POWERUPS:
		var b := _make_button(POWERUPS[key][0], 15)
		b.tooltip_text = POWERUPS[key][1]
		b.pressed.connect(_on_powerup_pressed.bind(key))
		power_box.add_child(b)
		powerup_buttons[key] = b
	target_menu = PopupMenu.new()
	target_menu.id_pressed.connect(_on_target_chosen)
	add_child(target_menu)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
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
		var peek_row := HBoxContainer.new()
		peek_row.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(name_label)
		if p != HUMAN:
			box.add_child(backs)
		box.add_child(info_label)
		box.add_child(peek_row)
		table.add_child(box)
		box.set_anchors_and_offsets_preset(presets[p], Control.PRESET_MODE_KEEP_SIZE)
		match presets[p]:
			Control.PRESET_CENTER_TOP:
				_set_offsets(box, -200, 200, 10, 190)
			Control.PRESET_CENTER_LEFT:
				_set_offsets(box, 20, 260, -90, 110)
			Control.PRESET_CENTER_RIGHT:
				_set_offsets(box, -260, -20, -90, 110)
			Control.PRESET_CENTER_BOTTOM:
				# Your seat is just a name tag at the bottom-left above the hand.
				box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
				_set_offsets(box, 20, 220, -230, -170)
		seats.append({"box": box, "name_label": name_label, "backs": backs, "info_label": info_label,
			"peek_row": peek_row})


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


## Background song loops for the whole session, across menu and games.
func _start_music() -> void:
	var stream: AudioStreamMP3 = MUSIC.duplicate()
	stream.loop = true
	music_player = AudioStreamPlayer.new()
	music_player.stream = stream
	music_player.volume_db = -6.0
	add_child(music_player)
	music_player.play()


func _show_menu() -> void:
	game_id += 1
	target_menu.hide()
	game_running = false
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
	locked = passed.duplicate()
	dead_pile = deck.slice(players * 13)
	powerup_used = {}
	powerup_uses_left = MAX_POWERUP_USES
	lead_steal_armed = false
	peek_player = -1
	peek_cards = []
	flash_text = ""
	finish_order = []
	last_combo = {}
	last_cards = []
	last_player = -1
	log_lines = []
	game_start_ms = Time.get_ticks_msec()
	game_running = true

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
	dead_pile.append_array(last_cards)
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
			# A Hand-Locked round winner doesn't get the lead; it passes on.
			_new_round(i if hands[i].size() > 0 and not locked[i] else _next_active(i))
			return
		if hands[i].size() > 0 and not passed[i]:
			current = i
			return
	_new_round(_next_active(current))


func _new_round(leader: int) -> void:
	if lead_steal_armed and leader != HUMAN and hands[HUMAN].size() > 0:
		lead_steal_armed = false
		_log("Lead Steal! You take the lead from %s." % names[leader])
		leader = HUMAN
	passed.fill(false)
	locked.fill(false)
	dead_pile.append_array(last_cards)
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
	target_menu.hide()
	for p in _active_players():
		finish_order.append(p)
	_refresh_ui()
	var lines := []
	for i in finish_order.size():
		lines.append("%s  —  %s" % [PLACE_NAMES[i], names[finish_order[i]]])
	var headline := "You win!" if finish_order[0] == HUMAN else "%s wins." % names[finish_order[0]]
	game_running = false
	var length := _format_time(_elapsed_seconds())
	timer_label.text = "Time  " + length
	_log("Game over after %s." % length)
	result_label.text = headline + "\n\n" + "\n".join(lines) + "\n\nGame length:  " + length
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
	var remaining := cards.duplicate()
	for v in hand_views:
		v.selected = remaining.has(v.card)
		remaining.erase(v.card)
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
		var peek_row: HBoxContainer = seat.peek_row
		for child in peek_row.get_children():
			child.queue_free()
		if p == peek_player:
			var still_held := []
			var hand_copy: Array = hands[p].duplicate()
			for c in peek_cards:
				if hand_copy.has(c):
					hand_copy.erase(c)
					still_held.append(c)
			if not still_held.is_empty():
				peek_row.add_child(_make_label("Peeked:", 14, TURN_COLOR))
			for c in still_held:
				var v := CardView.new()
				v.setup(c, true, false, 0.6)
				peek_row.add_child(v)

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
	_refresh_powerups()
	if flash_text != "":
		status_label.text = flash_text
		flash_text = ""


func _process(_delta: float) -> void:
	if game_running and table.visible:
		timer_label.text = "Time  " + _format_time(_elapsed_seconds())


func _elapsed_seconds() -> int:
	return (Time.get_ticks_msec() - game_start_ms) / 1000


func _format_time(seconds: int) -> String:
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _log(line: String) -> void:
	log_lines.append(line)
	while log_lines.size() > 8:
		log_lines.pop_front()
	print(line)


# ============================================================================
# Power-ups
# ============================================================================

func _opponents_with_cards() -> Array:
	var result := []
	for p in _active_players():
		if p != HUMAN:
			result.append(p)
	return result


## Why `key` can't be used right now, or "" if it can.
func _powerup_block(key: String) -> String:
	if not powerup_enabled.get(key, false):
		return "off"
	if powerup_used.has(key):
		return "used"
	if powerup_uses_left <= 0:
		return "no uses left"
	if not table.visible or overlay.visible or hands[HUMAN].is_empty():
		return "unavailable"
	match key:
		"peek":
			if _opponents_with_cards().is_empty():
				return "no targets"
		"lead_steal":
			pass  # can be armed at any time; fires when the next round starts
		"lucky_draw":
			if current != HUMAN:
				return "your turn only"
			if dead_pile.is_empty():
				return "dead pile empty"
		"suit_up":
			if current != HUMAN:
				return "your turn only"
		"hand_lock":
			if current != HUMAN:
				return "your turn only"
			if _lockable_opponents().is_empty():
				return "no targets"
	return ""


func _lockable_opponents() -> Array:
	var result := []
	for p in _opponents_with_cards():
		if not locked[p]:
			result.append(p)
	return result


func _refresh_powerups() -> void:
	var any_enabled := false
	for key in POWERUPS:
		var b: Button = powerup_buttons[key]
		b.visible = powerup_enabled.get(key, false)
		any_enabled = any_enabled or b.visible
		var block := _powerup_block(key)
		b.disabled = block != ""
		var label: String = POWERUPS[key][0]
		if key == "lead_steal" and lead_steal_armed:
			label += " (armed)"
		elif block == "used":
			label += " (used)"
		b.text = label
	powerup_title.visible = any_enabled
	powerup_title.text = "Power-ups: %d use%s left" % [powerup_uses_left, "" if powerup_uses_left == 1 else "s"]


func _consume_powerup(key: String) -> void:
	powerup_used[key] = true
	powerup_uses_left -= 1


func _on_powerup_pressed(key: String) -> void:
	if _powerup_block(key) != "":
		return
	match key:
		"peek", "hand_lock":
			var targets := _opponents_with_cards() if key == "peek" else _lockable_opponents()
			if targets.size() == 1:
				_apply_targeted_powerup(key, targets[0])
				return
			pending_target_power = key
			target_menu.clear()
			for p in targets:
				target_menu.add_item(names[p], p)
			target_menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))
		"lead_steal":
			_consume_powerup(key)
			lead_steal_armed = true
			_log("You armed Lead Steal — you'll lead the next round.")
			_refresh_ui()
		"suit_up", "lucky_draw":
			_apply_card_powerup(key)


func _on_target_chosen(p: int) -> void:
	var key := pending_target_power
	pending_target_power = ""
	if key != "" and _powerup_block(key) == "":
		_apply_targeted_powerup(key, p)


func _apply_targeted_powerup(key: String, p: int) -> void:
	_consume_powerup(key)
	if key == "peek":
		var shown: Array = hands[p].duplicate()
		shown.shuffle()
		peek_player = p
		peek_cards = shown.slice(0, 3)
		peek_cards.sort()
		_log("You peeked at %s's hand." % names[p])
	else:
		locked[p] = true
		passed[p] = true
		_log("You Hand-Locked %s for the rest of this round." % names[p])
	_refresh_ui()


## Suit Up / Lucky Draw act on exactly one selected card.
func _apply_card_powerup(key: String) -> void:
	var sel := _selected_cards()
	if sel.size() != 1:
		flash_text = "Select exactly one card, then press %s." % POWERUPS[key][0]
		_refresh_buttons()
		return
	var card: int = sel[0]
	if card == required_card:
		flash_text = "The %s must be played to open the game." % Rules.card_name(card)
		_refresh_buttons()
		return
	var new_card: int
	if key == "suit_up":
		if Rules.suit(card) == 3:
			flash_text = "Hearts is already the highest suit."
			_refresh_buttons()
			return
		new_card = card + 1
		_log("Suit Up: your %s became the %s." % [Rules.card_name(card), Rules.card_name(new_card)])
	else:
		new_card = dead_pile.pop_at(randi() % dead_pile.size())
		dead_pile.append(card)
		_log("Lucky Draw: you discarded the %s and drew the %s." % [
			Rules.card_name(card), Rules.card_name(new_card)])
	_consume_powerup(key)
	hands[HUMAN].erase(card)
	hands[HUMAN].append(new_card)
	hands[HUMAN].sort()
	_rebuild_hand()
	_refresh_ui()
