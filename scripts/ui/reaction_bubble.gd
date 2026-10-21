extends PanelContainer
## Her in-match speech bubble. Listens to card events on the EventBus and shows a
## random line from the opponent's profile; never blocks play and fades on its own.
## Which event maps to which dialogue key is in tuning.json -> reactions.lines.

var label: Label
var subtitle: Label
var tween: Tween
var last_text := ""


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.94)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	style.border_color = Color(0.9, 0.5, 0.7)
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	add_child(box)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.15, 0.08, 0.12))
	box.add_child(label)
	subtitle = Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.35, 0.3, 0.4))
	box.add_child(subtitle)
	visible = false


func _ready() -> void:
	for e in EventBus.CARD_EVENTS:
		EventBus.connect(e, _on_card_event.bind(e))


func _on_card_event(info: Dictionary, event: String) -> void:
	var key := event
	if info.has("by"):
		key = "%s:%s" % [event, info.by]
	elif info.has("winner"):
		key = "%s:%s" % [event, info.winner]
	var dialogue_key: String = Config.value("reactions.lines", {}).get(key, "")
	if dialogue_key == "":
		return
	if key == "powerup_used:player" and not info.get("first", true):
		return  # "Cheating already?" only fits the first one
	var minor: bool = Config.value("reactions.minor_events", []).has(event)
	if minor and (_showing() or randf() >= Config.value("reactions.minor_line_chance", 0.5)):
		return
	var profile = Characters.profile(info.get("opponent_id", ""))
	if profile == null:
		return
	show_line(profile.line_entry(dialogue_key, GameState.char_state(profile.id()).unlocks))


func show_line(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	last_text = entry.text
	label.text = entry.text
	var translation: String = entry.get("translation", "")
	subtitle.text = "(%s)" % translation
	subtitle.visible = translation != "" and GameState.settings.get("subtitles", true)
	visible = true
	modulate.a = 1.0
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_interval(Config.value("reactions.bubble_seconds", 3.5))
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): visible = false)


## Hides the bubble right away (e.g. when the date ends).
func dismiss() -> void:
	if tween:
		tween.kill()
	visible = false


func _showing() -> bool:
	return visible and modulate.a > 0.5
