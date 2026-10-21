extends Control
## End-of-day summary: what happened today (unlocks earned, dates, trivia, talks, gifts).
## Affection is deliberately not shown here: how she feels stays a mystery.

signal closed                  # "Start Day N" (or, after the last day, back to the menu)
signal menu_requested          # "Return to main menu" mid-story

const Character := preload("res://scripts/character.gd")

var body: Label
var title: Label
var continue_button: Button
var menu_button: Button


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
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	col.add_child(title)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 19)
	col.add_child(body)
	continue_button = Button.new()
	continue_button.add_theme_font_size_override("font_size", 22)
	continue_button.pressed.connect(func(): closed.emit())
	col.add_child(continue_button)
	menu_button = Button.new()
	menu_button.text = "Return to main menu"
	menu_button.add_theme_font_size_override("font_size", 18)
	menu_button.pressed.connect(func(): menu_requested.emit())
	col.add_child(menu_button)


## `final`: the last day of the story, which also shows totals for the whole story.
func refresh(final := false) -> void:
	title.text = "The End" if final else "End of Day %d" % GameState.day
	continue_button.text = "Back to main menu" if final else "Start Day %d" % (GameState.day + 1)
	menu_button.visible = not final
	var lines := ["Day %d of %d is over." % [GameState.day, Calendar.days()], ""]
	for id in Characters.ids():
		var profile = Characters.profile(id)
		var st: Dictionary = GameState.char_state(id)
		lines.append("%s" % profile.full_name())
		var earned: Array = st.unlocks.filter(func(u): return not st.start_unlocks.has(u))
		lines.append("    Unlocked: %s" % (", ".join(earned.map(func(u): return Character.pretty(u)))
			if not earned.is_empty() else "nothing new today"))
		lines.append("")
	lines.append("Date matches today:  %d won, %d lost" % [GameState.count_log("match_won"),
		GameState.count_log("match_lost")])
	lines.append("Money:  $%d  (%+d today)" % [GameState.money, GameState.money - GameState.day_start_money])
	var right := GameState.count_log("trivia_correct")
	lines.append("Trivia:  %d of %d right   ·   Talks: %d   ·   Gifts given: %d" % [right,
		right + GameState.count_log("trivia_wrong"), GameState.count_log("talk"), GameState.count_log("gift")])
	if final:
		lines.append("")
		lines.append("Over the whole story")
		lines.append("    Date matches: %d won, %d lost" % [GameState.match_record.wins, GameState.match_record.losses])
	body.text = "\n".join(lines)
