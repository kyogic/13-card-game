extends PanelContainer
## Debug panel (F1 or `): set affection, move time, and fire card events by hand.

var character_select: OptionButton
var affection_spin: SpinBox
var in_date_check: CheckBox
var info_label: Label


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.88)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN  # widen leftwards, never off-screen
	offset_left = -440
	offset_right = -10
	offset_top = 10
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	col.add_child(_label("DEBUG  (F1 to close)", Color(1, 0.6, 0.2)))
	character_select = OptionButton.new()
	col.add_child(character_select)
	info_label = _label("", Color(0.8, 0.8, 0.8))
	col.add_child(info_label)

	col.add_child(_label("Affection", Color.WHITE))
	var row := HBoxContainer.new()
	affection_spin = SpinBox.new()
	affection_spin.max_value = 100
	affection_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(affection_spin)
	row.add_child(_button("Set", func(): Affection.set_value(_char(), int(affection_spin.value))))
	col.add_child(row)

	col.add_child(_label("Time", Color.WHITE))
	var time_row := HBoxContainer.new()
	time_row.add_child(_button("New story", func(): EventBus.fire("new_story_requested")))
	time_row.add_child(_button("Next slot", func(): Calendar.next_slot()))
	time_row.add_child(_button("+$100", func(): Economy.earn(100, "debug")))
	col.add_child(time_row)

	col.add_child(_label("Card events", Color.WHITE))
	in_date_check = CheckBox.new()
	in_date_check.text = "Treat as a date (affection counts)"
	in_date_check.toggled.connect(func(on): GameState.in_date = on)
	col.add_child(in_date_check)
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	for e in [["match_started", {}], ["hand_won", {}], ["hand_lost", {}],
			["bomb_played", {"by": "player"}], ["bomb_played", {"by": "opponent"}], ["two_saved", {}],
			["powerup_used", {"by": "player", "id": "wild", "first": true}],
			["powerup_used", {"by": "opponent", "id": "lead_steal", "first": true}],
			["match_ended", {"winner": "player", "score": [2, 0]}],
			["match_ended", {"winner": "opponent", "score": [0, 2]}]]:
		var text: String = e[0] + (" (%s)" % e[1].values()[0] if not e[1].is_empty() else "")
		grid.add_child(_button(text, fire_card_event.bind(e[0], e[1])))
	for id in Characters.ids():
		character_select.add_item(id)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		action.call()
		refresh())
	return b


func _char() -> String:
	return character_select.get_item_text(character_select.selected) if character_select.item_count > 0 else ""


func fire_card_event(event: String, info: Dictionary) -> void:
	var payload := info.duplicate()
	payload["opponent_id"] = _char()
	EventBus.fire(event, payload)


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	var id := _char()
	if id == "":
		return
	affection_spin.value = Affection.value(id)
	in_date_check.set_pressed_no_signal(GameState.in_date)
	info_label.text = "%s · slot %d (%s) · time %d · affection %d" % [id, GameState.slot_index,
		Calendar.slot_name(), GameState.time_left, Affection.value(id)]
