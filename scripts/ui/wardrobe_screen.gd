extends Control
## Wardrobe: a tab per girl. Buy outfits with Story Mode money (only from inside a story),
## and pick the one she always wears; "Take off" lets her choose for each date again.

signal closed

var character_id := ""
var can_buy := false           # true when opened from a story (money available)
var title: Label
var tabs: HBoxContainer
var money_label: Label
var row: HBoxContainer
var slots := {}                # outfit id -> {image, button}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.08, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	title = _label("", 40, Color(1, 0.9, 0.4))
	box.add_child(title)
	tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	money_label = _label("", 18, Color(1, 0.85, 0.2))
	box.add_child(money_label)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	box.add_child(_label("Outfits you buy are yours to keep, even in a new story. If she isn't wearing a "
		+ "particular outfit, she picks one of yours for each date.", 14, Color(0.75, 0.75, 0.85)))
	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func():
		visible = false
		closed.emit())
	box.add_child(close)
	visible = false


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(900, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func open(buying_allowed: bool, id := "") -> void:
	can_buy = buying_allowed
	for c in tabs.get_children():
		tabs.remove_child(c)
		c.queue_free()
	for cid in Wardrobe.outfits:
		var b := Button.new()
		b.text = Characters.profile(cid).first_name() if Characters.profile(cid) else cid.capitalize()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 0)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(show_page.bind(cid))
		tabs.add_child(b)
	visible = true
	show_page(id if id != "" else Wardrobe.outfits.keys()[0])


func show_page(id: String) -> void:
	character_id = id
	var ids: Array = Wardrobe.outfits.keys()
	for i in tabs.get_child_count():
		tabs.get_child(i).set_pressed_no_signal(ids[i] == id)
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	slots.clear()
	for o in Wardrobe.outfits_for(id):
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 6)
		var image := TextureRect.new()
		image.texture = load(o.path)
		image.custom_minimum_size = Vector2(180, 290)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(image)
		var name_label := Label.new()
		name_label.text = o.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		slot.add_child(name_label)
		var button := Button.new()
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_pressed.bind(o.id))
		slot.add_child(button)
		row.add_child(slot)
		slots[o.id] = {"image": image, "button": button}
	refresh()


func refresh() -> void:
	var name: String = Characters.profile(character_id).first_name() if Characters.profile(character_id) \
		else character_id.capitalize()
	title.text = "%s's Wardrobe" % name
	var player := SaveGame.slot != 0
	if can_buy:
		money_label.text = "You have $%d" % GameState.money
	elif player:
		money_label.text = "Save slot %d  ·  Outfits are bought with money you earn in Story Mode." % SaveGame.slot
	else:
		money_label.text = "Start a story to begin your wardrobe."
	for o in Wardrobe.outfits_for(character_id):
		var slot: Dictionary = slots[o.id]
		var button: Button = slot.button
		var owned: bool = Wardrobe.is_owned(o.id)
		slot.image.modulate = Color.WHITE if owned else Color(0.15, 0.15, 0.15)
		if not player:
			button.text = "Free" if owned else "$%d" % o.price
			button.disabled = true
		elif Wardrobe.worn(character_id) == o.id:
			button.text = "Wearing  (take off)"
			button.disabled = false
		elif owned:
			button.text = "Wear"
			button.disabled = false
		elif can_buy:
			button.text = "Buy  $%d" % o.price
			button.disabled = not Wardrobe.can_buy(o.id)
		else:
			button.text = "$%d in Story Mode" % o.price
			button.disabled = true


func _on_pressed(id: String) -> void:
	if Wardrobe.worn(character_id) == id:
		Wardrobe.take_off(character_id)
	elif Wardrobe.is_owned(id):
		Wardrobe.wear(id)
	elif can_buy:
		Wardrobe.buy(id)
	refresh()
