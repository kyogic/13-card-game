extends Control
## Tien Len prototype: menu, table UI and turn flow. The whole UI is built in code.

const Rules := preload("res://scripts/rules.gd")
const Character := preload("res://scripts/character.gd")
const AI := preload("res://scripts/ai.gd")
const CardView := preload("res://scripts/card_view.gd")
const MUSIC := preload("res://audio/cardgame_song.mp3")

const HUMAN := 0
var CPU_DELAY := 0.9
const PLACE_NAMES := ["1st", "2nd", "3rd", "4th"]
const TURN_COLOR := Color(1.0, 0.85, 0.2)
const IDLE_COLOR := Color(0.9, 0.95, 0.9)
const MAX_POWERUP_USES := 2
## Wardrobe outfits per character (data/outfits.json). The first of each is free.
const OUTFITS_PATH := "res://data/outfits.json"
const UNLOCK_COST := 1
## Bumping this resets everyone's coins once on their next launch (outfits are kept).
const COINS_VERSION := 2
const MATCH_WINS_NEEDED := 2   # 2-player games are best of 3
## Opponent for 2-player games started from the menu (dates pass their own).
const DEFAULT_OPPONENT_PATH := "res://data/characters/jessica.json"
## Late-game threshold for the `two_saved` event: you win a round still holding a 2
## you were dealt, with at most this many cards left. Fired once per game.
## Overridden by events.two_saved_max_cards in the tuning config when it's loaded.
const TWO_SAVED_MAX_CARDS := 3
const FRAME_2P_LEFT := 430      # 2-player: the table frame starts here; Jessica stands to its left
## key -> [button name, description]. Each power-up can be used once per game.
const POWERUPS := {
	"suit_up": ["Suit Up", "Turn one card into the Heart of the same rank (the highest suit)."],
	"wild": ["Wild Card", "Make one card wild: it becomes whatever card completes your play."],
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
var wild_card := -1            # value of the card in your hand made wild, or -1
var pending_target_power := ""
var flash_text := ""           # one-shot status message shown on the next refresh
var game_start_ms := 0

# --- 2-player match + progression -------------------------------------------
var save_path := "user://save.cfg"
var coins := 0
var unlocked: Array = ["jessica"]
var outfits := {}              # character id -> [{id, name, path}], from OUTFITS_PATH
var selected_outfits := {}     # character id -> outfit id picked in the Wardrobe
var wardrobe_character := ""   # whose outfits the Wardrobe is showing
var date_outfit := ""          # outfit she wore to the current date (random from unlocked)
var pending_cpu_play: Array = []  # a CPU play decided ahead of its turn (her Second Wind)
var match_wins := [0, 0]       # games won this match by [you, opponent]
var match_game := 0            # which game of the match is being played
var last_game_winner := -1     # leads the next game of the match

# --- 2-player opponent --------------------------------------------------------
## {id, name, full_name, portrait, tuning, signature_powerup}; see Character.to_opponent().
var opponent := {}
var opponent_name := "Jessica"
var in_date := false           # match was started by the dating layer
var her_powerup_used := false  # her signature power-up, once per game
var her_round_best := -1       # highest rank she played this round (to know she "thought she'd win")
var dealt_twos: Array = []     # 2s you were dealt this game (for `two_saved`)
var two_saved_fired := false
var game_running := false
## The EventBus autoload, looked up at runtime so the card game also runs without the
## dating layer (e.g. in tests); with no bus, events simply aren't sent.
var bus: Node

# --- UI ---------------------------------------------------------------------
var menu: Control
var menu_pages := {}           # "main" / "story" / "quickplay" -> VBoxContainer
var table: Control
var seats: Array = []          # per player: {box, name_label, backs, info_label}
var pile_label: Label
var pile_cards: HBoxContainer
var pile_center: VBoxContainer
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
var menu_coins_label: Label
var wardrobe: Control
var wardrobe_coins_label: Label
var wardrobe_slots := {}       # outfit id -> {image, button}, for the girl being shown
var wardrobe_row: HBoxContainer
var wardrobe_title: Label
var wardrobe_tabs: HBoxContainer
var portrait: TextureRect
var nameplate: Label
var menu_button: Button
var overlay_menu_button: Button
var table_frame: Panel
var match_label: Label
var again_button: Button


func _ready() -> void:
	randomize()
	for key in POWERUPS:
		powerup_enabled[key] = true
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.36, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_set_opponent(Character.load_profile(DEFAULT_OPPONENT_PATH).to_opponent())
	_load_outfits()
	bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.date_requested.connect(_on_date_requested)
	_load_progress()
	_start_music()
	_build_menu()
	_build_wardrobe()
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
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 10)
	menu.add_child(pages)
	pages.add_child(_make_label("TIEN LEN", 52, Color(1, 0.9, 0.4)))
	pages.add_child(_make_label("Thirteen — Vietnamese card game", 20, IDLE_COLOR))
	pages.add_child(_spacer(6))

	# Main page: the two modes, the wardrobe, and settings shared by both modes.
	var main_page := _menu_page(pages, "main")
	main_page.add_child(_menu_button("Story Mode", "Date Jessica and Arisa over three days", 26,
		_show_menu_page.bind("story")))
	main_page.add_child(_menu_button("Quickplay", "Jump straight into a card game", 26,
		_show_menu_page.bind("quickplay")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var wardrobe_button := _make_button("Wardrobe", 20)
	wardrobe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wardrobe_button.pressed.connect(_show_wardrobe)
	row.add_child(wardrobe_button)
	var quit := _make_button("Quit", 20)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(get_tree().quit)
	row.add_child(quit)
	main_page.add_child(row)
	main_page.add_child(_spacer(6))
	main_page.add_child(_make_label("Power-ups  (toggle on/off — each usable once, up to %d per game)" % MAX_POWERUP_USES,
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
	main_page.add_child(grid_center)
	var music_toggle := CheckButton.new()
	music_toggle.text = "Background music"
	music_toggle.button_pressed = true
	music_toggle.add_theme_font_size_override("font_size", 16)
	music_toggle.toggled.connect(func(on): music_player.stream_paused = not on)
	var music_center := CenterContainer.new()
	music_center.add_child(music_toggle)
	main_page.add_child(music_center)

	# Story Mode: the dating sim (handled by the dating layer through the EventBus).
	var story_page := _menu_page(pages, "story")
	story_page.add_child(_make_label("Story Mode", 30, Color(1, 0.85, 0.4)))
	story_page.add_child(_make_label("Three days. Two girls. You can only be in one place at a time.", 17, IDLE_COLOR))
	story_page.add_child(_menu_button("New Story", "Start over from Day 1", 24,
		func(): if bus: bus.fire("new_story_requested")))
	story_page.add_child(_menu_button("Continue Story", "Pick up from your last save", 24,
		func(): if bus: bus.fire("continue_story_requested")))
	story_page.add_child(_menu_button("Back", "", 20, _show_menu_page.bind("main")))

	# Quickplay: straight into a card game.
	var quick_page := _menu_page(pages, "quickplay")
	quick_page.add_child(_make_label("Quickplay", 30, Color(1, 0.85, 0.4)))
	quick_page.add_child(_menu_button("4 Players  —  You vs 3 CPU (full deck)", "", 24, _start_game.bind(4)))
	quick_page.add_child(_menu_button("2 Players  —  You vs %s (half deck, best of 3)" % opponent_name,
		"Win the match to earn a coin for the Wardrobe", 24, _start_match))
	quick_page.add_child(_spacer(6))
	quick_page.add_child(_make_label(
		"Get rid of all your cards first.  3 is low, 2 is high.  Suits: Spades < Clubs < Diamonds < Hearts.\n" +
		"Play singles, pairs, triples, four-of-a-kind, straights (3+) or 3+ consecutive pairs.\n" +
		"Beat the table with the same kind and size but a higher top card, or pass.\n" +
		"Passing locks you out until the round resets.  Bombs (4-of-a-kind, consecutive pairs) chop 2s.",
		15, Color(0.85, 0.92, 0.85)))
	quick_page.add_child(_menu_button("Back", "", 20, _show_menu_page.bind("main")))

	menu_coins_label = _make_label("", 24, Color(1, 0.85, 0.2))
	menu_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	menu_coins_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(menu_coins_label, -260, -20, 14, 50)
	add_child(menu_coins_label)
	_show_menu_page("main")


func _menu_page(parent: Control, page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	menu_pages[page_name] = page
	return page


func _menu_button(text: String, tooltip: String, font_size: int, action: Callable) -> Button:
	var b := _make_button(text, font_size)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(560, 0)
	b.pressed.connect(action)
	return b


func _show_menu_page(page_name: String) -> void:
	for p in menu_pages:
		menu_pages[p].visible = p == page_name


func _build_table() -> void:
	table = Control.new()
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)

	# The game is contained in its own framed "window" (felt with a wooden rim).
	table_frame = Panel.new()
	var felt := StyleBoxFlat.new()
	felt.bg_color = Color(0.06, 0.42, 0.24)
	felt.border_color = Color(0.42, 0.27, 0.12)
	felt.set_border_width_all(6)
	felt.set_corner_radius_all(16)
	felt.shadow_color = Color(0, 0, 0, 0.45)
	felt.shadow_size = 10
	table_frame.add_theme_stylebox_override("panel", felt)
	table_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table.add_child(table_frame)

	# Centre pile.
	var center := VBoxContainer.new()
	pile_center = center
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
	bottom.offset_bottom = -14
	bottom.offset_left = 16
	bottom.offset_right = -16
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
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.85))
	table.add_child(log_label)
	menu_button = _make_button("Menu", 16)
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.offset_left = -90
	menu_button.offset_right = -12
	menu_button.offset_top = 10
	menu_button.offset_bottom = 44
	menu_button.pressed.connect(_on_menu_button)
	table.add_child(menu_button)
	timer_label = _make_label("", 20, IDLE_COLOR)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(timer_label, -260, -100, 12, 42)
	table.add_child(timer_label)
	match_label = _make_label("", 17, Color(1, 0.85, 0.2))
	match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	match_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(match_label, -330, -12, 50, 76)
	table.add_child(match_label)

	# 2-player opponent: Jessica stands outside the table frame, full-length.
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_set_offsets(portrait, 0, FRAME_2P_LEFT - 10, 10, -78)
	add_child(portrait)
	move_child(portrait, table.get_index())
	nameplate = _make_label("", 28, Color(1, 0.85, 0.4))
	nameplate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_set_offsets(nameplate, 0, FRAME_2P_LEFT - 10, -74, -36)
	add_child(nameplate)

	portrait.visible = false
	nameplate.visible = false

	# Power-up panel (top-right, under the menu button).
	var power_box := VBoxContainer.new()
	power_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_set_offsets(power_box, -230, -12, 82, 280)
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
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.2, 0.12)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_make_label("Game Over", 44, Color(1, 0.9, 0.4)))
	result_label = _make_label("", 24, Color.WHITE)
	box.add_child(result_label)
	again_button = _make_button("Play Again", 22)
	again_button.pressed.connect(_on_again_pressed)
	box.add_child(again_button)
	overlay_menu_button = _make_button("Main Menu", 22)
	overlay_menu_button.pressed.connect(_show_menu)
	box.add_child(overlay_menu_button)


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
				if num_players == 2:
					# Top-left of the frame, clear of the timer and power-ups.
					_set_offsets(box, -300, -60, 20, 180)
				else:
					_set_offsets(box, -200, 200, 10, 190)
			Control.PRESET_CENTER_LEFT:
				_set_offsets(box, 20, 260, -90, 110)
			Control.PRESET_CENTER_RIGHT:
				_set_offsets(box, -260, -20, -90, 110)
			Control.PRESET_CENTER_BOTTOM:
				# Your seat is just a name tag above the hand: bottom-left, or beside the
				# buttons in the narrower 2-player frame so it can't collide with the status line.
				if num_players == 2:
					box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
					_set_offsets(box, -175, -16, -205, -145)
				else:
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
	wardrobe.visible = false
	table.visible = false
	portrait.visible = false
	nameplate.visible = false
	overlay.visible = false
	menu_coins_label.visible = true
	menu_coins_label.text = "Coins: %d" % coins


# ============================================================================
# Game flow
# ============================================================================

func _start_match() -> void:
	match_wins = [0, 0]
	match_game = 0
	last_game_winner = -1
	_emit("match_started", {"date": in_date})
	_start_game(2)


func _start_game(players: int) -> void:
	game_id += 1
	num_players = players
	names = ["You"]
	for i in range(1, players):
		names.append("CPU %d" % i if players > 2 else opponent_name)
	if players == 2:
		match_game += 1

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
	her_powerup_used = false
	her_round_best = -1
	pending_cpu_play = []
	dealt_twos = hands[HUMAN].filter(func(c): return Rules.rank(c) == Rules.RANK_TWO)
	two_saved_fired = false
	wild_card = -1
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
	menu_coins_label.visible = false
	overlay.visible = false
	table.visible = true
	_build_seats()
	_apply_layout()
	_update_portrait()
	if players == 2 and last_game_winner >= 0:
		# Later games of a match: the previous winner leads with anything.
		required_card = -1
		current = last_game_winner
		_log("Game %d of the match. %s won the last game and %s." % [
			match_game, names[current], "lead" if current == HUMAN else "leads"])
	else:
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
	var cards := pending_cpu_play
	pending_cpu_play = []
	if cards.is_empty():
		cards = AI.choose_play(hands[current], last_combo, required_card, _danger_for(current),
			opponent.get("tuning", {}) if num_players == 2 else {})
	if cards.is_empty():
		_do_pass(current)
	else:
		_do_play(current, cards)


## `from_hand` are the cards leaving the hand when they differ from what is played
## (a wild card is played as the card it stands in for).
func _do_play(p: int, cards: Array, from_hand: Array = []) -> void:
	var combo := Rules.analyze(cards)
	for c in (from_hand if not from_hand.is_empty() else cards):
		hands[p].erase(c)
	cards = cards.duplicate()
	cards.sort()
	dead_pile.append_array(last_cards)
	last_combo = combo
	last_cards = cards
	last_player = p
	required_card = -1
	_log("%s played %s." % [names[p], Rules.type_name(combo)])
	if num_players == 2:
		_track_play(p, combo)

	if hands[p].is_empty():
		finish_order.append(p)
		_log("%s is out of cards — %s place!" % [names[p], PLACE_NAMES[finish_order.size() - 1]])
	if p == HUMAN:
		_rebuild_hand()
	if hands[p].is_empty() and _active_players().size() <= 1:
		_emit_hand_result(p)  # the winning play also wins the last hand
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
			if _opponent_second_wind():
				return
			# A Hand-Locked round winner doesn't get the lead; it passes on.
			_new_round(i if hands[i].size() > 0 and not locked[i] else _next_active(i))
			return
		if hands[i].size() > 0 and not passed[i]:
			current = i
			return
	_new_round(_next_active(current))


func _new_round(leader: int) -> void:
	var round_winner := last_player
	if lead_steal_armed and leader != HUMAN and hands[HUMAN].size() > 0:
		lead_steal_armed = false
		_log("Lead Steal! You take the lead from %s." % names[leader])
		leader = HUMAN
	elif num_players == 2:
		_emit_hand_result(round_winner)
		leader = _opponent_round_end(round_winner, leader)
	her_round_best = -1
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
	var text := headline + "\n\n" + "\n".join(lines) + "\n\nGame length:  " + length
	again_button.text = "Play Again"
	overlay_menu_button.visible = not in_date
	if num_players == 2:
		text = "%s   ·   Game length:  %s\n%s" % [headline, length, _record_match_result(finish_order[0])]
		if _match_over():
			_emit("match_ended", {"winner": "player" if finish_order[0] == HUMAN else "opponent",
				"score": match_wins.duplicate(), "date": in_date})
			if in_date:
				again_button.text = "Continue the day"
	result_label.text = text
	overlay.visible = true
	_refresh_match_label()


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
	var played := _resolve_wild(cards)
	if cards.has(wild_card):
		var stand_in: int = played[cards.find(wild_card)]
		_log("Your wild card was played as the %s." % Rules.card_name(stand_in))
		wild_card = -1
	_do_play(HUMAN, played, cards)


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
## Replaces the wild card (if selected) with the strongest card that makes the
## selection a legal play. Keeps positions so callers can find the stand-in.
func _resolve_wild(cards: Array) -> Array:
	var idx := cards.find(wild_card)
	if idx < 0:
		return cards
	var best := cards
	var best_score := -1
	for v in 52:
		var trial := cards.duplicate()
		trial[idx] = v
		var combo := Rules.analyze(trial)
		if not Rules.can_beat(combo, last_combo):
			continue
		if required_card >= 0 and not trial.has(required_card):
			continue
		var bomb: bool = combo.type == Rules.Type.QUAD or combo.type == Rules.Type.DOUBLE_SEQ
		var score: int = combo.top + (100 if bomb else 0)
		if score > best_score:
			best_score = score
			best = trial
	return best


func _play_error(selected: Array) -> String:
	if selected.is_empty():
		return "Select cards to play."
	var cards := _resolve_wild(selected)
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
		v.wild = c == wild_card
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
		# Overlap the cards when a long straight would not fit.
		var n := last_cards.size()
		var room := pile_center.size.x
		var w := CardView.CARD_SIZE.x
		var gap := 6.0 if n * (w + 6) <= room else (room - w * n) / maxf(n - 1, 1)
		pile_cards.add_theme_constant_override("separation", int(gap))
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
			var sel := _selected_cards()
			var played := _resolve_wild(sel)
			status_label.text = "Ready: %s" % Rules.type_name(Rules.analyze(played))
			if sel.has(wild_card):
				status_label.text += "  (wild = %s)" % Rules.card_name(played[sel.find(wild_card)])
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
	while log_lines.size() > (5 if num_players == 2 else 8):
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
		"lead_steal":
			pass  # can be armed at any time; fires when the next round starts
		"lucky_draw":
			if current != HUMAN:
				return "your turn only"
			if dead_pile.is_empty():
				return "dead pile empty"
		"suit_up", "wild":
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
	if num_players == 2:
		_emit("powerup_used", {"by": "player", "id": key,
			"first": powerup_uses_left == MAX_POWERUP_USES - 1})


func _on_powerup_pressed(key: String) -> void:
	if _powerup_block(key) != "":
		return
	match key:
		"hand_lock":
			var targets := _lockable_opponents()
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
		"suit_up", "lucky_draw", "wild":
			_apply_card_powerup(key)


func _on_target_chosen(p: int) -> void:
	var key := pending_target_power
	pending_target_power = ""
	if key != "" and _powerup_block(key) == "":
		_apply_targeted_powerup(key, p)


func _apply_targeted_powerup(key: String, p: int) -> void:
	_consume_powerup(key)
	if key == "hand_lock":
		locked[p] = true
		passed[p] = true
		_log("You Hand-Locked %s for the rest of this round." % names[p])
	_refresh_ui()


## Suit Up / Lucky Draw / Wild Card act on exactly one selected card.
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
	if card == wild_card:
		flash_text = "That card is already wild."
		_refresh_buttons()
		return
	if key == "wild":
		_consume_powerup(key)
		wild_card = card
		_log("Wild Card: your %s is now wild." % Rules.card_name(card))
		_rebuild_hand()
		_refresh_ui()
		return
	var new_card: int
	if key == "suit_up":
		if Rules.suit(card) == 3:
			flash_text = "That card is already a Heart."
			_refresh_buttons()
			return
		new_card = Rules.rank(card) * 4 + 3
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


# ============================================================================
# 2-player match, coins and wardrobe
# ============================================================================

## Records a finished 2-player game and returns the match summary for the results screen.
func _record_match_result(winner: int) -> String:
	match_wins[winner] += 1
	last_game_winner = winner
	var score := "Match:  You %d – %d %s" % [match_wins[0], match_wins[1], opponent_name]
	if match_wins[winner] < MATCH_WINS_NEEDED:
		again_button.text = "Next Game"
		return score + "   (best of 3)"
	again_button.text = "New Match"
	if winner == HUMAN:
		coins += 1
		_save_progress()
		_log("You won the match! +1 coin.")
		return score + "\nYou won the match!  +1 coin  (%d total)" % coins
	_log("%s won the match." % opponent_name)
	return score + "\n%s won the match." % opponent_name


func _match_over() -> bool:
	return match_wins.max() >= MATCH_WINS_NEEDED


func _on_again_pressed() -> void:
	if in_date and _match_over():
		_finish_date(true)
	elif num_players != 2:
		_start_game(num_players)
	elif _match_over():
		_start_match()
	else:
		_start_game(2)


func _refresh_match_label() -> void:
	match_label.visible = num_players == 2
	match_label.text = "Game %d  ·  You %d – %d %s" % [match_game, match_wins[0], match_wins[1], opponent_name]


func _load_outfits() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OUTFITS_PATH))
	outfits = {}
	if parsed is Dictionary:
		for cid in parsed:
			if parsed[cid] is Array and not parsed[cid].is_empty():
				outfits[cid] = parsed[cid]
	for cid in outfits:
		if not unlocked.has(outfits[cid][0].id):
			unlocked.append(outfits[cid][0].id)  # first outfit is free
		selected_outfits[cid] = outfits[cid][0].id
	wardrobe_character = outfits.keys()[0] if not outfits.is_empty() else ""


func _all_outfits() -> Array:
	var all := []
	for cid in outfits:
		all.append_array(outfits[cid])
	return all


func _outfit(id: String) -> Dictionary:
	for o in _all_outfits():
		if o.id == id:
			return o
	return {}


## The outfit she wears in a quick match: the one selected for her in the Wardrobe.
func selected_outfit_for(character_id: String) -> String:
	return selected_outfits.get(character_id, "")


## Shows her outfit, full-length, in 2-player games: the date's random outfit on a date,
## otherwise the one selected in the Wardrobe.
func _update_portrait() -> void:
	portrait.visible = num_players == 2 and table.visible
	nameplate.visible = portrait.visible
	_refresh_match_label()
	nameplate.text = opponent.get("full_name", opponent_name)
	if portrait.visible:
		# Wardrobe outfits (if this opponent has any) replace the profile portrait.
		var outfit_id: String = date_outfit if in_date else selected_outfit_for(opponent.get("id", ""))
		var path: String = _outfit(outfit_id).get("path", opponent.get("portrait", ""))
		portrait.texture = load(path)


## Frames the table. In 2-player games the frame moves right to leave room for Jessica,
## the pile shifts left of the power-ups and the log moves under them.
func _apply_layout() -> void:
	if num_players == 2:
		# The whole table shrinks into a frame on the right; Jessica stands to its left.
		_set_offsets(table, FRAME_2P_LEFT, -10, 10, -10)
		_set_offsets(pile_center, -400, 150, -140, 40)
		log_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_set_offsets(log_label, -238, -14, 290, 470)
		log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		log_label.add_theme_font_size_override("font_size", 13)
	else:
		_set_offsets(table, 8, -8, 8, -8)
		_set_offsets(pile_center, -330, 330, -140, 40)
		log_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_set_offsets(log_label, 16, 600, 14, 200)
		log_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		log_label.add_theme_font_size_override("font_size", 14)


func _build_wardrobe() -> void:
	wardrobe = Control.new()
	wardrobe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wardrobe)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wardrobe.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	wardrobe_title = _make_label("", 44, Color(1, 0.9, 0.4))
	box.add_child(wardrobe_title)
	wardrobe_tabs = HBoxContainer.new()
	wardrobe_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	wardrobe_tabs.add_theme_constant_override("separation", 8)
	for cid in outfits:
		var tab := _make_button(cid.capitalize(), 20)
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(160, 0)
		tab.pressed.connect(_show_wardrobe_for.bind(cid))
		wardrobe_tabs.add_child(tab)
	box.add_child(wardrobe_tabs)
	wardrobe_coins_label = _make_label("", 20, Color(1, 0.85, 0.2))
	box.add_child(wardrobe_coins_label)
	wardrobe_row = HBoxContainer.new()
	wardrobe_row.add_theme_constant_override("separation", 16)
	wardrobe_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(wardrobe_row)
	var back := _make_button("Back", 20)
	back.pressed.connect(_show_menu)
	box.add_child(back)


func _show_wardrobe() -> void:
	menu.visible = false
	menu_coins_label.visible = false
	wardrobe.visible = true
	_show_wardrobe_for(wardrobe_character)


## Shows one girl's outfits (the tabs switch between girls).
func _show_wardrobe_for(character_id: String) -> void:
	wardrobe_character = character_id
	for c in wardrobe_row.get_children():
		wardrobe_row.remove_child(c)
		c.queue_free()
	wardrobe_slots.clear()
	for o in outfits.get(character_id, []):
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 6)
		var image := TextureRect.new()
		image.texture = load(o.path)
		image.custom_minimum_size = Vector2(180, 290)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(image)
		slot.add_child(_make_label(o.name, 20, IDLE_COLOR))
		var button := _make_button("", 18)
		button.pressed.connect(_on_outfit_pressed.bind(o.id))
		slot.add_child(button)
		wardrobe_row.add_child(slot)
		wardrobe_slots[o.id] = {"image": image, "button": button}
	var ids := outfits.keys()
	for i in wardrobe_tabs.get_child_count():
		wardrobe_tabs.get_child(i).set_pressed_no_signal(ids[i] == character_id)
	_refresh_wardrobe()


func _refresh_wardrobe() -> void:
	wardrobe_title.text = "%s's Wardrobe" % wardrobe_character.capitalize()
	wardrobe_coins_label.text = "Coins: %d   ·   Win a best-of-3 match against %s to earn a coin" % [
		coins, opponent_name]
	for o in outfits.get(wardrobe_character, []):
		var slot: Dictionary = wardrobe_slots[o.id]
		var button: Button = slot.button
		var owned := unlocked.has(o.id)
		slot.image.modulate = Color.WHITE if owned else Color(0.15, 0.15, 0.15)
		if o.id == selected_outfit_for(wardrobe_character):
			button.text = "Selected"
			button.disabled = true
		elif owned:
			button.text = "Select"
			button.disabled = false
		else:
			button.text = "Unlock  (%d coin)" % UNLOCK_COST
			button.disabled = coins < UNLOCK_COST


func _on_outfit_pressed(id: String) -> void:
	if _outfit(id).is_empty():
		return
	if not unlocked.has(id):
		if coins < UNLOCK_COST:
			return
		coins -= UNLOCK_COST
		unlocked.append(id)
	for cid in outfits:
		if outfits[cid].any(func(o): return o.id == id):
			selected_outfits[cid] = id
	_save_progress()
	_refresh_wardrobe()


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	coins = cfg.get_value("progress", "coins", 0)
	unlocked = cfg.get_value("progress", "unlocked", [])
	# Saves from before the character was named used "abg" ids.
	unlocked = unlocked.map(func(id): return id.replace("abg", "jessica"))
	var saved_selection: Dictionary = cfg.get_value("progress", "selected_outfits", {})
	if cfg.has_section_key("progress", "selected_outfit"):  # older saves: Jessica only
		saved_selection["jessica"] = str(cfg.get_value("progress", "selected_outfit")).replace("abg", "jessica")
	# Outfits taken out of the lineup (e.g. Smile): refund their coins.
	var known := _all_outfits().map(func(o): return o.id)
	for id in unlocked.filter(func(id): return not known.has(id)):
		unlocked.erase(id)
		coins += UNLOCK_COST
	for cid in outfits:
		if not unlocked.has(outfits[cid][0].id):
			unlocked.append(outfits[cid][0].id)
		var pick: String = saved_selection.get(cid, "")
		selected_outfits[cid] = pick if unlocked.has(pick) else outfits[cid][0].id
	if cfg.get_value("progress", "coins_version", 1) < COINS_VERSION:
		coins = 0  # one-time coin reset
		_save_progress()


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "coins", coins)
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "selected_outfits", selected_outfits)
	cfg.set_value("progress", "coins_version", COINS_VERSION)
	cfg.save(save_path)


# ============================================================================
# Opponent, dates and events for the dating layer
# ============================================================================

func _set_opponent(info: Dictionary) -> void:
	opponent = info
	opponent_name = info.get("name", "Opponent")


## The dating layer asks for a date: play a best-of-3 match against that character.
func _on_date_requested(info: Dictionary) -> void:
	_set_opponent(info.opponent)
	in_date = true
	date_outfit = random_unlocked_outfit()
	_start_match()


## She shows up to each date in a random outfit you've unlocked (kept for the whole match).
## Opponents without wardrobe outfits return "" and use their profile portrait.
func random_unlocked_outfit() -> String:
	var owned: Array = outfits.get(opponent.get("id", ""), []).filter(func(o): return unlocked.has(o.id))
	return owned.pick_random().id if not owned.is_empty() else ""


## Ends a date and hands control back to the dating layer.
func _finish_date(completed: bool) -> void:
	in_date = false
	_show_menu()
	if bus:
		bus.fire("date_closed", {"completed": completed})


func _on_menu_button() -> void:
	if in_date:
		_finish_date(false)  # leaving a date early
	else:
		_show_menu()


## Emits a card event for the dating layer. Only 2-player games have an opponent character.
func _emit(event: String, info: Dictionary = {}) -> void:
	if num_players != 2 and event != "match_started":
		return
	info["opponent_id"] = opponent.get("id", "")
	if bus:
		bus.fire(event, info)


func _emit_hand_result(round_winner: int) -> void:
	if num_players != 2 or round_winner < 0:
		return
	if round_winner != HUMAN:
		_emit("hand_lost")
		return
	_emit("hand_won")
	# two_saved: you won this hand while still holding a 2 you were dealt, late in the game.
	var held := dealt_twos.filter(func(c): return hands[HUMAN].has(c))
	var config := get_node_or_null("/root/Config")
	var max_cards: int = config.int_value("events.two_saved_max_cards", TWO_SAVED_MAX_CARDS) if config \
		else TWO_SAVED_MAX_CARDS
	if not two_saved_fired and not held.is_empty() and hands[HUMAN].size() <= max_cards:
		two_saved_fired = true
		_emit("two_saved")


func _track_play(p: int, combo: Dictionary) -> void:
	var bomb: bool = combo.type == Rules.Type.QUAD or combo.type == Rules.Type.DOUBLE_SEQ
	if bomb:
		_emit("bomb_played", {"by": "player" if p == HUMAN else "opponent"})
	if p != HUMAN:
		her_round_best = maxi(her_round_best, Rules.RANK_TWO if bomb else Rules.rank(combo.top))


## Her signature power-up (from the opponent's card_ai): Lead Steal, once per game,
## right after losing a round she thought she'd win (she'd played a King or better).
## Returns who leads the new round.
func _opponent_round_end(round_winner: int, leader: int) -> int:
	var her := 1
	var thought_she_won := her_round_best >= Rules.RANK_NAMES.find("K")
	if opponent.get("signature_powerup", "") == "lead_steal" and not her_powerup_used \
			and round_winner != her and leader != her and thought_she_won and hands[her].size() > 0:
		her_powerup_used = true
		_log("%s used Lead Steal!" % opponent_name)
		_emit("powerup_used", {"by": "opponent", "id": "lead_steal", "first": true})
		return her
	return leader


## Her signature Second Wind (from the opponent's card_ai), once per game: she has passed,
## the round is about to go to you, and she jumps back in with a play that beats yours.
## Returns true if she used it (her play is queued for her turn).
func _opponent_second_wind() -> bool:
	var her := 1
	if num_players != 2 or last_player != HUMAN or opponent.get("signature_powerup", "") != "second_wind":
		return false
	if her_powerup_used or not passed[her] or locked[her] or hands[her].is_empty():
		return false
	var cards := AI.choose_play(hands[her], last_combo, -1, 0, opponent.get("tuning", {}))
	if cards.is_empty():
		return false
	her_powerup_used = true
	passed[her] = false
	current = her
	pending_cpu_play = cards
	_log("%s used Second Wind!" % opponent_name)
	_emit("powerup_used", {"by": "opponent", "id": "second_wind", "first": true})
	return true
