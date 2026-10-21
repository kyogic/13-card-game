extends Control
## Story Mode: three save slots. Each slot is a player with their own story, journal and
## wardrobe. Continue, start a New Story (keeps journal and outfits), or Delete (erases all).

signal continue_pressed(slot: int)
signal new_story_pressed(slot: int)
signal back_pressed

var rows := {}                 # slot -> {info, continue, new, delete}
var confirm: ConfirmationDialog
var pending := Callable()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.22)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(820, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	col.add_child(_label("Story Mode", 40, Color(1, 0.85, 0.4)))
	col.add_child(_label("Three days. Two girls. You can only be in one place at a time.", 17,
		Color(0.85, 0.85, 0.95)))
	for n in range(1, SaveGame.SLOT_COUNT + 1):
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.17, 0.3)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(14)
		panel.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var info := _label("", 17, Color.WHITE)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var cont := _button("Continue", func(): continue_pressed.emit(n))
		var fresh := _button("New Story", _on_new.bind(n))
		var delete := _button("Delete", _on_delete.bind(n))
		for b in [cont, fresh, delete]:
			row.add_child(b)
		col.add_child(panel)
		rows[n] = {"info": info, "continue": cont, "new": fresh, "delete": delete}
	col.add_child(_button("Back", func(): back_pressed.emit()))
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(func():
		if pending.is_valid():
			pending.call())
	add_child(confirm)
	visible = false


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(120, 40)
	b.pressed.connect(action)
	return b


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	for n in rows:
		var info: Dictionary = SaveGame.slot_info(n)
		var r: Dictionary = rows[n]
		if not info.exists:
			r.info.text = "Slot %d   ·   Empty" % n
		else:
			var where: String = "Story finished" if info.story_over else (
				"Day %d of %d · %s" % [info.day, Calendar.days(), "end of day" if info.day_over else info.slot_name]) \
				if info.has_story else "No story yet"
			r.info.text = "Slot %d   ·   %s\n%d outfits  ·  %d journal entries  ·  saved %s" % [n, where,
				info.outfits, info.facts, info.saved_at.replace("T", " ")]
		r.continue.disabled = not info.get("has_story", false)
		r.delete.disabled = not info.exists


## Asks before replacing a slot's story (its journal and outfits stay).
func _on_new(n: int) -> void:
	if not SaveGame.slot_info(n).get("has_story", false):
		new_story_pressed.emit(n)
		return
	_ask("Start a new story in Slot %d?\nThe current story there ends. Your journal and outfits are kept." % n,
		func(): new_story_pressed.emit(n))


func _on_delete(n: int) -> void:
	_ask("Delete Slot %d?\nThis erases its story, journal and outfits. It can't be undone." % n, func():
		SaveGame.delete_slot(n)
		refresh())


func _ask(text: String, then: Callable) -> void:
	pending = then
	confirm.dialog_text = text
	confirm.popup_centered()
