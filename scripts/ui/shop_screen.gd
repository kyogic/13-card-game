extends Control
## Shop overlay: today's stock, prices, your money and how many of each you already have.
## Buying takes no time.

signal closed

const Character := preload("res://scripts/character.gd")

var money_label: Label
var list: VBoxContainer
var buy_buttons := {}          # item id -> Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.2)
	style.border_color = Color(1, 0.85, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	col.add_child(title)
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 18)
	col.add_child(money_label)
	var note := Label.new()
	note.text = "New stock every morning. Shopping takes no time."
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	col.add_child(note)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	col.add_child(list)
	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(func():
		visible = false
		closed.emit())
	col.add_child(close)
	visible = false


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	money_label.text = "You have $%d" % GameState.money
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	buy_buttons.clear()
	for item in GameState.shop_stock:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.text = Character.pretty(item)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var owned := Label.new()
		owned.text = "have %d" % GameState.inventory.get(item, 0)
		owned.add_theme_font_size_override("font_size", 14)
		owned.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		row.add_child(owned)
		var b := Button.new()
		b.text = "Buy  $%d" % Economy.price(item)
		b.custom_minimum_size = Vector2(110, 0)
		b.disabled = not Economy.can_buy(item)
		b.pressed.connect(func():
			Economy.buy(item)
			refresh())
		row.add_child(b)
		list.add_child(row)
		buy_buttons[item] = b
