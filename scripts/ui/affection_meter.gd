extends VBoxContainer
## Placeholder affection meter for one character: "Affection 27/100 · Curious", a bar,
## and a floating +7 / -5 pop-up whenever the value changes.

var character_id := ""
var label: Label
var bar: ProgressBar


func _init() -> void:
	add_theme_constant_override("separation", 2)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 0.75, 0.85))
	add_child(label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.45, 0.65)
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)


func _ready() -> void:
	EventBus.affection_changed.connect(_on_changed)


func set_character(id: String) -> void:
	character_id = id
	refresh()


func refresh() -> void:
	var profile = Characters.profile(character_id)
	if profile == null:
		return
	var v: int = Affection.value(character_id)
	bar.max_value = profile.affection_max()
	bar.value = v
	label.text = "Affection %d/%d  ·  %s" % [v, profile.affection_max(), profile.stage(v).get("label", "")]


func _on_changed(info: Dictionary) -> void:
	if info.character_id != character_id:
		return
	refresh()
	if is_visible_in_tree():
		_popup(info.delta)


func _popup(delta: int) -> void:
	var p := Label.new()
	p.text = "%+d" % delta
	p.add_theme_font_size_override("font_size", 26)
	p.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if delta > 0 else Color(1, 0.45, 0.45))
	p.add_theme_color_override("font_outline_color", Color.BLACK)
	p.add_theme_constant_override("outline_size", 4)
	p.top_level = true
	p.global_position = global_position + Vector2(size.x * 0.5 - 20, -30)
	add_child(p)
	var t := p.create_tween()
	t.tween_property(p, "global_position:y", p.global_position.y - 40,
		Config.value("ui.popup_seconds", 1.2))
	t.parallel().tween_property(p, "modulate:a", 0.0, Config.value("ui.popup_seconds", 1.2))
	t.tween_callback(p.queue_free)
