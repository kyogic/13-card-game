extends Control
## The dating layer: sits above the card game and owns the day's screens
## (conversation; calendar and summary come next), the in-match reaction bubble and
## the affection meter shown during dates. Talks to the card game only via EventBus.

const ConversationScreen := preload("res://scripts/ui/conversation_screen.gd")
const ReactionBubble := preload("res://scripts/ui/reaction_bubble.gd")
const AffectionMeter := preload("res://scripts/ui/affection_meter.gd")
const DEMO_DAY_PATH := "res://data/demo_day.json"

var demo_day: Dictionary = {}
var screens: Control           # opaque full-screen container for the day's screens
var conversation
var bubble
var date_meter


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	screens = Control.new()
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screens)
	conversation = ConversationScreen.new()
	conversation.action_taken.connect(_on_action_taken)
	conversation.left.connect(_on_conversation_left)
	screens.add_child(conversation)

	# During a date: her speech bubble (top-left) and affection meter (under her name).
	bubble = ReactionBubble.new()
	bubble.position = Vector2(14, 10)
	bubble.custom_minimum_size = Vector2(390, 0)
	bubble.size = Vector2(390, 0)
	add_child(bubble)
	date_meter = AffectionMeter.new()
	date_meter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	date_meter.offset_left = 20
	date_meter.offset_right = 400
	date_meter.offset_top = -36
	date_meter.offset_bottom = -6
	add_child(date_meter)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DEMO_DAY_PATH))
	demo_day = parsed if parsed is Dictionary else {}


func _ready() -> void:
	EventBus.demo_day_requested.connect(func(_info): start_day())
	EventBus.date_requested.connect(_on_date_requested)
	EventBus.date_closed.connect(_on_date_closed)
	EventBus.match_ended.connect(_on_match_ended)
	hide_all()


func hide_all() -> void:
	screens.visible = false
	date_meter.visible = false


func start_day() -> void:
	GameState.reset(demo_day.get("starter_inventory", {}))
	for id in Characters.ids():
		Affection.ensure(id)
		GameState.char_state(id).start_affection = Affection.value(id)
	_open_conversation("jessica", "pho_spot")


func _open_conversation(id: String, location: String) -> void:
	GameState.location = location
	screens.visible = true
	conversation.open(id, location, location.capitalize())
	conversation.set_status("")


func _on_action_taken(_kind: String) -> void:
	conversation.refresh()


func _on_conversation_left() -> void:
	hide_all()


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
	GameState.log_event("match", "%s the date match %d–%d." % ["Won" if won else "Lost",
		info.score[0], info.score[1]])


func _on_date_closed(_info: Dictionary) -> void:
	GameState.in_date = false
	date_meter.visible = false
	_open_conversation(conversation.character_id, GameState.location)
