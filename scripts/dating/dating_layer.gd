extends Control
## The dating layer: sits above the card game and owns the day's screens (calendar,
## conversation, summary), the in-match reaction bubble and the affection meter shown
## during dates. Talks to the card game only through the EventBus.

const ConversationScreen := preload("res://scripts/ui/conversation_screen.gd")
const CalendarScreen := preload("res://scripts/ui/calendar_screen.gd")
const SummaryScreen := preload("res://scripts/ui/summary_screen.gd")
const DebugPanel := preload("res://scripts/ui/debug_panel.gd")
const JournalScreen := preload("res://scripts/ui/journal_screen.gd")
const ShopScreen := preload("res://scripts/ui/shop_screen.gd")
const WardrobeScreen := preload("res://scripts/ui/wardrobe_screen.gd")
const SlotsScreen := preload("res://scripts/ui/slots_screen.gd")
const ReactionBubble := preload("res://scripts/ui/reaction_bubble.gd")
const AffectionMeter := preload("res://scripts/ui/affection_meter.gd")

var screens: Control           # opaque full-screen container for the day's screens
var calendar
var conversation
var summary
var journal
var shop
var wardrobe
var slots
var debug_panel
var bubble
var date_meter


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	screens = Control.new()
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screens)
	calendar = CalendarScreen.new()
	calendar.location_picked.connect(_on_location_picked)
	calendar.wait_pressed.connect(_on_wait)
	calendar.save_pressed.connect(_on_save)
	calendar.menu_pressed.connect(_return_to_menu)
	screens.add_child(calendar)
	conversation = ConversationScreen.new()
	conversation.can_afford = func(kind): return Calendar.can_afford(kind)
	conversation.action_taken.connect(_on_action_taken)
	conversation.left.connect(_show_calendar)
	screens.add_child(conversation)
	journal = JournalScreen.new()
	summary = SummaryScreen.new()
	summary.closed.connect(_on_summary_closed)
	summary.menu_requested.connect(_return_to_menu)
	screens.add_child(summary)
	screens.add_child(journal)  # overlays above the other screens
	shop = ShopScreen.new()
	shop.closed.connect(func(): calendar.refresh())
	screens.add_child(shop)
	calendar.shop_pressed.connect(func(): shop.open())
	wardrobe = WardrobeScreen.new()
	wardrobe.closed.connect(_on_wardrobe_closed)
	screens.add_child(wardrobe)
	calendar.wardrobe_pressed.connect(func(): wardrobe.open(true))
	slots = SlotsScreen.new()
	slots.continue_pressed.connect(continue_story)
	slots.new_story_pressed.connect(start_story)
	slots.back_pressed.connect(hide_all)
	screens.add_child(slots)
	calendar.journal_pressed.connect(func(): journal.open())
	conversation.journal_pressed.connect(func(): journal.open(conversation.character_id))

	# During a date: her speech bubble down by her feet (so it never covers her face),
	# growing upwards from just above her name, and her affection meter under her name.
	bubble = ReactionBubble.new()
	bubble.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bubble.offset_left = 14
	bubble.offset_right = 404
	bubble.offset_top = -90
	bubble.offset_bottom = -84
	add_child(bubble)
	date_meter = AffectionMeter.new()
	date_meter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	date_meter.offset_left = 20
	date_meter.offset_right = 400
	date_meter.offset_top = -36
	date_meter.offset_bottom = -6
	add_child(date_meter)
	debug_panel = DebugPanel.new()
	add_child(debug_panel)


func _ready() -> void:
	EventBus.story_menu_requested.connect(func(_info): _show_slots())
	EventBus.new_story_requested.connect(func(info): start_story(info.get("slot", 0)))
	EventBus.date_requested.connect(_on_date_requested)
	EventBus.date_closed.connect(_on_date_closed)
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.time_advanced.connect(_on_time_advanced)
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.continue_story_requested.connect(func(info): continue_story(info.get("slot", 0)))
	EventBus.wardrobe_requested.connect(func(_info): _open_wardrobe_from_menu())
	EventBus.money_changed.connect(func(_info):
		if conversation.visible:
			_refresh_status())
	hide_all()


func hide_all() -> void:
	SaveGame.playing = false
	screens.visible = false
	journal.visible = false
	shop.visible = false
	wardrobe.visible = false
	slots.visible = false
	date_meter.visible = false
	bubble.dismiss()


func _show_slots() -> void:
	screens.visible = true
	calendar.visible = false
	conversation.visible = false
	summary.visible = false
	slots.open()


## Starts a new story in save slot `slot` (0 = the active slot, or slot 1).
func start_story(slot := 0) -> void:
	if slot == 0:
		slot = SaveGame.slot if SaveGame.slot != 0 else 1
	slots.visible = false
	SaveGame.new_story(slot)
	SaveGame.playing = true
	var names: Array = Characters.ids().map(func(id): return Characters.profile(id).first_name())
	calendar.show_message("%d days. %s are out there somewhere, but you can only be in one place at a time."
		% [Calendar.days(), " and ".join(names)])
	_show_calendar()


## Loads the story in save slot `slot` (0 = the active slot); starts one if it has none.
func continue_story(slot := 0) -> void:
	if slot == 0:
		slot = SaveGame.slot if SaveGame.slot != 0 else 1
	slots.visible = false
	if not SaveGame.load_game(slot):
		start_story(slot)
		return
	SaveGame.playing = true
	if Calendar.day_over:
		_show_summary()
		return
	calendar.show_message("Welcome back. It's %s." % Calendar.slot_name().to_lower())
	_show_calendar()


## From the main menu: browse and wear owned outfits (buying needs a story's money).
func _open_wardrobe_from_menu() -> void:
	screens.visible = true
	calendar.visible = false
	conversation.visible = false
	summary.visible = false
	slots.visible = false
	wardrobe.open(false)


func _on_wardrobe_closed() -> void:
	if calendar.visible:
		calendar.refresh()
	else:
		hide_all()  # opened from the main menu


## Saves and goes back to the main menu; Continue Story picks up right here.
func _return_to_menu() -> void:
	SaveGame.save_game()
	hide_all()


func _on_save() -> void:
	if SaveGame.save_game():
		calendar.show_message("Game saved.")


func _show_calendar() -> void:
	screens.visible = true
	conversation.visible = false
	summary.visible = false
	calendar.visible = true
	calendar.refresh()


func _on_location_picked(location: String) -> void:
	if not Calendar.location_unlocked(location):
		return
	var here: Array = Calendar.characters_at(location)
	if here.is_empty():
		calendar.show_message("You head to the %s... nobody you know is here." % Calendar.location_name(location))
		GameState.log_event("travel", "%s: nobody at the %s." % [Calendar.slot_name(), Calendar.location_name(location)])
		Calendar.spend("travel_empty")
		calendar.refresh()
		return
	GameState.location = location
	calendar.visible = false
	conversation.open(here[0], location, Calendar.location_name(location))
	_refresh_status()


func _on_wait() -> void:
	calendar.show_message("You kill some time.")
	Calendar.end_slot()


func _on_action_taken(kind: String) -> void:
	Calendar.spend(kind)  # may move on to the next slot (see _on_time_advanced)
	_refresh_status()


func _refresh_status() -> void:
	conversation.set_status("%s  ·  time left %d/%d  ·  $%d" % [Calendar.slot_name(), GameState.time_left,
		Calendar.units_per_slot(), GameState.money])


func _on_time_advanced(info: Dictionary) -> void:
	if info.slot_index == 0:
		return
	# Slot used up: whatever was happening, you're back to choosing where to go.
	calendar.show_message("Time flies. It's %s now. (Autosaved.)" % Calendar.slot_name().to_lower())
	if not GameState.in_date:
		SaveGame.save_game()
	if screens.visible and not GameState.in_date and not summary.visible:
		_show_calendar()


func _on_date_requested(info: Dictionary) -> void:
	GameState.in_date = true
	screens.visible = false
	date_meter.set_character(info.character_id)
	date_meter.visible = true


func _on_match_ended(info: Dictionary) -> void:
	if not GameState.in_date:
		return
	var won: bool = info.winner == "player"
	GameState.match_record["wins" if won else "losses"] += 1
	GameState.log_event("match_won" if won else "match_lost", "%s the date match %d–%d." % [
		"Won" if won else "Lost", info.score[0], info.score[1]])


func _on_date_closed(info: Dictionary) -> void:
	GameState.in_date = false
	date_meter.visible = false
	bubble.dismiss()
	if not info.get("completed", true):
		GameState.log_event("date_left", "Left the date early.")
	screens.visible = true
	Calendar.end_slot()  # a date uses up the rest of the slot
	if Calendar.day_over:
		_show_summary()
	else:
		_show_calendar()


func _on_day_ended(_info: Dictionary) -> void:
	SaveGame.save_game()
	if not GameState.in_date:
		_show_summary()  # during a date it shows once the date closes


func _show_summary() -> void:
	screens.visible = true
	calendar.visible = false
	conversation.visible = false
	summary.visible = true
	summary.refresh(Calendar.is_final_day())


## "Start Day N" after a day's summary, or back to the menu when the story is over.
func _on_summary_closed() -> void:
	if Calendar.story_over():
		_return_to_menu()
		return
	Calendar.start_next_day()
	calendar.show_message("Day %d. A new morning." % GameState.day)
	SaveGame.save_game()
	_show_calendar()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_F1, KEY_QUOTELEFT]:
		debug_panel.toggle()
		get_viewport().set_input_as_handled()
