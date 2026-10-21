extends Control
## End-of-day summary: affection gained, stage reached, unlocks earned, match record.

signal closed

const Character := preload("res://scripts/character.gd")

var body: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.08, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(700, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var title := Label.new()
	title.text = "End of the Day"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	col.add_child(title)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 19)
	col.add_child(body)
	var back := Button.new()
	back.text = "Back to main menu"
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func(): closed.emit())
	col.add_child(back)


func refresh() -> void:
	var lines := ["Day %d is over." % GameState.day, ""]
	for id in Characters.ids():
		var profile = Characters.profile(id)
		var st: Dictionary = GameState.char_state(id)
		var gained: int = st.affection - st.start_affection
		lines.append("%s" % profile.full_name())
		lines.append("    Affection: %d → %d  (%+d)" % [st.start_affection, st.affection, gained])
		var stage: String = profile.stage(st.affection).get("label", "")
		var start_stage: String = profile.stage(st.start_affection).get("label", "")
		lines.append("    Stage: %s%s" % [stage, "  (new!)" if stage != start_stage else ""])
		var earned: Array = st.unlocks.filter(func(u): return not st.start_unlocks.has(u))
		lines.append("    Unlocks earned: %s" % (", ".join(earned.map(func(u): return Character.pretty(u)))
			if not earned.is_empty() else "none"))
		lines.append("")
	lines.append("Date matches:  %d won, %d lost" % [GameState.match_record.wins, GameState.match_record.losses])
	var right := GameState.count_log("trivia_correct")
	lines.append("Trivia:  %d of %d right   ·   Talks: %d   ·   Gifts given: %d" % [right,
		right + GameState.count_log("trivia_wrong"), GameState.count_log("talk"), GameState.count_log("gift")])
	body.text = "\n".join(lines)
