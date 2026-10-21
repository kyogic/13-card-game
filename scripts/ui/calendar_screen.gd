extends Control
## Placeholder calendar: the current slot, time left, and where to go.
## Emits location_picked(id) or wait_pressed; the dating layer decides what happens.

signal location_picked(id: String)
signal wait_pressed
signal save_pressed
signal menu_pressed
signal journal_pressed
signal shop_pressed
signal wardrobe_pressed

const Character := preload("res://scripts/character.gd")

var title_label: Label
var time_label: Label
var message_label: Label
var location_box: GridContainer
var location_buttons := {}     # id -> Button
var inventory_label: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.22)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(888, 0)
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	title_label = _label(40, Color(1, 0.85, 0.4))
	col.add_child(title_label)
	time_label = _label(20, Color(0.85, 0.85, 0.95))
	col.add_child(time_label)
	message_label = _label(18, Color(1, 0.75, 0.85))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(message_label)
	col.add_child(_label(20, Color.WHITE, "Where do you go?"))
	location_box = GridContainer.new()
	location_box.columns = 2
	location_box.add_theme_constant_override("h_separation", 8)
	location_box.add_theme_constant_override("v_separation", 8)
	col.add_child(location_box)
	for id in Calendar.location_ids():
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(440, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): location_picked.emit(id))
		location_box.add_child(b)
		location_buttons[id] = b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var wait := Button.new()
	wait.text = "Wait"
	wait.tooltip_text = "Skip to the next part of the day"
	wait.add_theme_font_size_override("font_size", 16)
	wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wait.pressed.connect(func(): wait_pressed.emit())
	row.add_child(wait)
	var save := Button.new()
	save.text = "Save game"
	save.add_theme_font_size_override("font_size", 16)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func(): save_pressed.emit())
	row.add_child(save)
	var journal := Button.new()
	journal.text = "Journal"
	journal.add_theme_font_size_override("font_size", 16)
	journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal.pressed.connect(func(): journal_pressed.emit())
	row.add_child(journal)
	var shop := Button.new()
	shop.text = "Shop"
	shop.add_theme_font_size_override("font_size", 16)
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop.pressed.connect(func(): shop_pressed.emit())
	row.add_child(shop)
	var wardrobe := Button.new()
	wardrobe.text = "Wardrobe"
	wardrobe.add_theme_font_size_override("font_size", 16)
	wardrobe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wardrobe.pressed.connect(func(): wardrobe_pressed.emit())
	row.add_child(wardrobe)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.tooltip_text = "Saves, then returns to the main menu"
	menu.add_theme_font_size_override("font_size", 16)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): menu_pressed.emit())
	row.add_child(menu)
	col.add_child(row)
	inventory_label = _label(15, Color(0.75, 0.8, 0.9))
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(inventory_label)


func _label(font_size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func show_message(text: String) -> void:
	message_label.text = text


func refresh() -> void:
	title_label.text = "Day %d of %d  ·  %s" % [GameState.day, Calendar.days(), Calendar.slot_name()]
	time_label.text = "Time left this %s: %d / %d" % [Calendar.slot_name().to_lower(), GameState.time_left,
		Calendar.units_per_slot()]
	for id in location_buttons:
		var b: Button = location_buttons[id]
		var reason: String = Calendar.lock_reason(id)
		b.disabled = reason != ""
		var here: Array = Calendar.characters_at(id).map(func(c): return Characters.profile(c).first_name())
		var lines: Array = [Calendar.location_name(id)]
		if not here.is_empty():
			lines.append("♥ %s %s here" % [" & ".join(here), "is" if here.size() == 1 else "are"])
		if reason != "":
			lines.append("[locked: %s]" % reason)
		b.text = "\n".join(lines)
		b.add_theme_color_override("font_color", Color(1, 0.75, 0.85) if not here.is_empty() else Color(0.85, 0.85, 0.9))
		b.add_theme_color_override("font_disabled_color",
			Color(0.75, 0.55, 0.65) if not here.is_empty() else Color(0.5, 0.5, 0.55))
	var items := []
	for g in GameState.inventory:
		if GameState.inventory[g] > 0:
			items.append("%s ×%d" % [Character.pretty(g), GameState.inventory[g]])
	inventory_label.text = "$%d   ·   Gifts: %s" % [GameState.money, ", ".join(items) if not items.is_empty() else "none"]
