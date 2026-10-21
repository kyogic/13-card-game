extends PanelContainer
## Visual-novel style dialogue box: speaker name, typewriter text, optional English
## subtitle for Vietnamese lines, click (or Enter/Space) to advance.
##
## play(lines) takes [{speaker, text, translation?}], where speaker is a display name
## ("" for narration). Emits `finished` after the last line is dismissed.

signal finished

var speaker_label: Label
var text_label: Label
var subtitle_label: Label
var hint_label: Label
var lines: Array = []
var index := -1
var typing := false
var shown := 0.0               # characters revealed so far (float for smooth typing)


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.1, 0.92)
	style.border_color = Color(0.9, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	speaker_label = _label(20, Color(1, 0.8, 0.5))
	box.add_child(speaker_label)
	text_label = _label(20, Color.WHITE)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(200, 0)
	box.add_child(text_label)
	subtitle_label = _label(16, Color(0.75, 0.8, 0.9))
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle_label)
	hint_label = _label(14, Color(0.7, 0.7, 0.7))
	hint_label.text = "click to continue  >"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint_label)


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func play(new_lines: Array) -> void:
	lines = new_lines
	index = -1
	visible = true
	_next()


## Shows a single line that stays until replaced (no click needed), e.g. a prompt.
func show_static(speaker: String, text: String, translation := "") -> void:
	lines = []
	index = -1
	typing = false
	_fill({"speaker": speaker, "text": text, "translation": translation})
	text_label.visible_characters = -1
	hint_label.visible = false


## Re-applies the subtitle setting to the line on screen (after the toggle changes).
func refresh_subtitle() -> void:
	subtitle_label.visible = subtitle_label.text != "" and GameState.settings.get("subtitles", true)


func is_busy() -> bool:
	return index >= 0 and index < lines.size()


## Click / key: finish the current line instantly, or move to the next one.
func advance() -> void:
	if not is_busy():
		return
	if typing:
		typing = false
		text_label.visible_characters = -1
		hint_label.visible = true
	else:
		_next()


func _next() -> void:
	index += 1
	if index >= lines.size():
		index = -1
		hint_label.visible = false
		finished.emit()
		return
	_fill(lines[index])
	shown = 0.0
	text_label.visible_characters = 0
	typing = true
	hint_label.visible = false


func _fill(entry: Dictionary) -> void:
	speaker_label.text = entry.get("speaker", "")
	speaker_label.visible = speaker_label.text != ""
	text_label.text = entry.get("text", "")
	# Narration reads as italics-style in grey; dialogue in white.
	text_label.add_theme_color_override("font_color",
		Color.WHITE if speaker_label.visible else Color(0.8, 0.8, 0.85))
	var translation: String = entry.get("translation", "")
	subtitle_label.text = "(%s)" % translation if translation != "" else ""
	subtitle_label.visible = translation != "" and GameState.settings.get("subtitles", true)


func _process(delta: float) -> void:
	if not typing:
		return
	shown += delta * Config.value("ui.typewriter_chars_per_second", 45)
	text_label.visible_characters = int(shown)
	if int(shown) >= text_label.text.length():
		typing = false
		text_label.visible_characters = -1
		hint_label.visible = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and is_busy() and event.is_action_pressed("ui_accept"):
		advance()
		get_viewport().set_input_as_handled()
