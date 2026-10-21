extends Control
## Journal overlay: one page per girl with what you've learned about her and how she
## reacted to your gifts. Opened from the calendar and from conversations.

signal closed

const Character := preload("res://scripts/character.gd")

var character_id := ""
var tabs: HBoxContainer
var title: Label
var progress_label: Label
var facts_label: Label
var gifts_label: Label


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
	style.bg_color = Color(0.98, 0.95, 0.9)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(900, 600)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var top := HBoxContainer.new()
	var heading := _label("Journal", 30, Color(0.45, 0.15, 0.3))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	top.add_child(tabs)
	col.add_child(top)
	title = _label("", 24, Color(0.2, 0.1, 0.15))
	col.add_child(title)
	progress_label = _label("", 16, Color(0.4, 0.3, 0.35))
	col.add_child(progress_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	facts_label = _label("", 17, Color(0.15, 0.1, 0.12))
	facts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(facts_label)
	col.add_child(scroll)
	gifts_label = _label("", 16, Color(0.3, 0.2, 0.25))
	gifts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(gifts_label)
	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(func():
		visible = false
		closed.emit())
	col.add_child(close)
	visible = false


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Opens on `id` (or the first girl).
func open(id := "") -> void:
	for c in tabs.get_children():
		tabs.remove_child(c)
		c.queue_free()
	for cid in Characters.ids():
		var b := Button.new()
		b.text = Characters.profile(cid).first_name()
		b.toggle_mode = true
		b.pressed.connect(show_page.bind(cid))
		tabs.add_child(b)
	visible = true
	show_page(id if id != "" else Characters.ids()[0])


func show_page(id: String) -> void:
	character_id = id
	var ids: Array = Characters.ids()
	for i in tabs.get_child_count():
		tabs.get_child(i).set_pressed_no_signal(ids[i] == id)
	var profile = Characters.profile(id)
	var st: Dictionary = GameState.char_state(id)
	title.text = "%s  “%s”" % [profile.full_name(), profile.data.get("nickname", profile.first_name())]
	if not st.met:
		progress_label.text = ""
		facts_label.text = "You haven't met her yet."
		gifts_label.text = ""
		return
	var entries: Array = Journal.entries(id)
	progress_label.text = "Things you know about her: %d of %d" % [entries.size(), Journal.total(id)]
	facts_label.text = "\n".join(entries.map(func(e): return "•  %s:  %s" % [e.label, e.text])) \
		if not entries.is_empty() else "Nothing yet. Talk to her to find out more."
	var notes: Dictionary = Journal.gift_notes(id)
	var parts := []
	for category in ["loved", "liked", "neutral", "disliked"]:
		if notes.has(category):
			parts.append("%s: %s" % [category.capitalize(), ", ".join(notes[category].map(
				func(g): return Character.pretty(g)))])
	gifts_label.text = "Gifts  ·  " + ("   |   ".join(parts) if not parts.is_empty() else "you haven't given her anything yet")
